//
//  MonthDetailsPageView.swift
//  Bookee
//
//  Per-month page view used inside the BudgetPageView carousel.
//  Renders the calendar, transactions, and attachments for one month.
//  Data arrays and sheets are owned by the parent (BudgetPageView); this view
//  exposes bindings for shared state and callbacks for row-level interactions.
//

import SwiftUI
import UIKit
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Calendar Tap Overlay

/// UIViewRepresentable overlay that provides tap handling on calendar days.
struct CalendarDragOverlay: UIViewRepresentable {
    let calendarDays: [Int?]
    let onToggleDay: (Int) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.calendarDays = calendarDays
        context.coordinator.onToggleDay = onToggleDay
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var calendarDays: [Int?] = []
        var onToggleDay: ((Int) -> Void)?

        private func day(at point: CGPoint, viewWidth: CGFloat) -> Int? {
            let col = Int(point.x * 7 / (viewWidth + 6))
            let row = Int(point.y / 53)
            guard col >= 0, col < 7, row >= 0 else { return nil }
            let index = row * 7 + col
            guard index >= 0, index < calendarDays.count else { return nil }
            return calendarDays[index]
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            let pt = g.location(in: view)
            guard let d = day(at: pt, viewWidth: view.bounds.width) else { return }
            onToggleDay?(d)
        }
    }
}

// MARK: - Month Page View

/// Per-month content view for the budget carousel.
/// Renders the calendar, transactions, and attachments for a single `yearMonth`.
/// All shared state (data arrays, filter, selection, sheets) is owned by BudgetPageView
/// and passed in via bindings/callbacks; only `selectedDays` is local to this page.
struct MonthPageView: View {
    // MARK: - Properties

    let yearMonth: YearMonth
    @Bindable var item: Item
    /// Incremented by BudgetPageView whenever the data cache is rebuilt (any transaction
    /// add/edit/delete). Used by the Equatable conformance to gate re-renders.
    let dataVersion: Int
    /// Incremented by BudgetPageView when selection or filter state changes. Because @Binding
    /// comparisons always read the current live value (both sides share the same @State
    /// storage), version counters are the correct way to detect binding value changes through
    /// .equatable(). @Bindable `item` changes use @Observable and bypass .equatable() directly.
    let renderVersion: Int
    /// Pre-computed expanded income/expense arrays for this month, built on a background
    /// thread by BudgetPageView. Using these instead of recomputing in body means zero
    /// day-scan loops during swipes.
    let precomputedData: MonthExpandedData

    /// Shared data arrays owned by the carousel host.
    @Binding var expenses: [Expense]
    @Binding var incomes: [Income]
    @Binding var attachments: [BudgetAttachment]
    @Binding var reallocations: [Reallocation]
    @Binding var odometerReadings: [OdometerReading]

    /// Shared filter/selection state.
    @Binding var selectedTransactionTypes: Set<TransactionFilter>
    @Binding var selectedTransactionCategories: Set<String>
    @Binding var selectedVehicleFilter: String?
    @Binding var selectedExpenses: Set<OccurrenceKey>
    @Binding var selectedIncomes: Set<OccurrenceKey>
    @Binding var selectedReallocations: Set<UUID>
    @Binding var selectedAttachments: Set<UUID>

    /// Callbacks that bubble row-level interactions up to the parent.
    let onEditExpense: (Expense, Date) -> Void
    let onEditIncome: (Income, Date) -> Void
    let onViewAttachment: (BudgetAttachment) -> Void
    let onEditReallocation: (Reallocation) -> Void
    let onDeleteReallocation: (Reallocation) -> Void
    let onEditOdometerReading: (OdometerReading) -> Void
    let onDeleteOdometerReading: (OdometerReading) -> Void
    let onDeleteExpense: (Expense) -> Void
    let onDeleteIncome: (Income) -> Void
    let onDuplicateExpense: (Expense, Date) -> Void
    let onDuplicateIncome: (Income, Date) -> Void
    let onPayOffExpense: (Expense) -> Void
    let yearRange: ClosedRange<Int>
    let onJumpToMonth: (YearMonth) -> Void

    // MARK: - Per-Page State

    /// Calendar day selection — owned by BudgetPageView and passed in as a binding.
    @Binding var selectedDays: Set<Int>

    /// When true, the page scrolls its list to the calendar section as soon as it appears.
    /// Used by BudgetPageView's "Current Month" button for pages that weren't yet mounted
    /// when the notification was posted (the notification handles already-mounted pages).
    var scrollToCalendarOnAppear: Bool = false
    var onScrollToCalendarTriggered: (() -> Void)? = nil

    /// True only for the page currently visible in the carousel. When false the
    /// list is instantly reset to the top so returning users always start fresh.
    var isActive: Bool = true

    // MARK: - AppStorage

    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @HighlightColorStorage private var highlightColor
    // MARK: - Computed Month Items

    private var monthAttachments: [BudgetAttachment] {
        attachments.filter { $0.month == yearMonth.month && $0.year == yearMonth.year && $0.deletedDate == nil }
    }

    private var monthAttachmentsBinding: Binding<[BudgetAttachment]> {
        Binding(
            get: { monthAttachments },
            set: { newValue in
                // Preserve soft-deleted attachments while replacing active ones
                let deletedOnes = attachments.filter { $0.month == yearMonth.month && $0.year == yearMonth.year && $0.deletedDate != nil }
                attachments.removeAll { $0.month == yearMonth.month && $0.year == yearMonth.year }
                attachments.append(contentsOf: newValue)
                attachments.append(contentsOf: deletedOnes)
            }
        )
    }

    // MARK: - Calendar Header Budget Metrics
    // Precomputed by buildMonthData off the main actor (see BudgetHelpers.swift) instead of
    // recomputed here on every body pass — these are always full-month totals, independent
    // of the live filter/day-selection state below. (Unused by the summary rows, which react
    // to filters/day-selection via `filteredHeaderTotals` instead — see below.)

    private var calendarMonthTaxableIncome: Decimal { precomputedData.taxableIncomeTotal }
    private var calendarMonthUntaxableIncome: Decimal { precomputedData.untaxableIncomeTotal }
    private var calendarMonthTaxSavings: Decimal { precomputedData.taxSavingsTotal }
    private var calendarHeaderEffectiveExpenses: Decimal { precomputedData.headerEffectiveExpenses }

    // MARK: - Transaction Totals (header display)

    private var activeMonthReallocations: [Reallocation]? {
        let reallocationRelated: Set<TransactionFilter> = [.reallocations, .positiveReallocation, .negativeReallocation]
        guard selectedTransactionTypes.isEmpty || !selectedTransactionTypes.isDisjoint(with: reallocationRelated), selectedDays.isEmpty else { return nil }
        let all = precomputedData.sortedActiveReallocations
        if !selectedTransactionTypes.contains(.reallocations) {
            return all.filter { r in
                (selectedTransactionTypes.contains(.positiveReallocation) && !r.isFromEntry) ||
                (selectedTransactionTypes.contains(.negativeReallocation) && r.isFromEntry)
            }
        }
        return all
    }

    private static let incomeOrExpenseFilters: Set<TransactionFilter> = [
        .income, .otherIncome, .taxableIncome, .recurringIncome, .oneTimeIncome,
        .expenses, .recurringExpenses, .paymentPlans, .oneTimeExpense
    ]
    private static let reallocationFilters: Set<TransactionFilter> = [.reallocations, .positiveReallocation, .negativeReallocation]

    /// True when the type filter contains at least one income/expense-related entry (parent
    /// or subtype) — each bucket's presence is independent, so Income/Expenses/Reallocations/
    /// Odometer can all be combined together rather than being mutually exclusive.
    private var hasIncomeOrExpenseFilter: Bool {
        !selectedTransactionTypes.isDisjoint(with: Self.incomeOrExpenseFilters)
    }

    private var hasReallocationFilter: Bool {
        !selectedTransactionTypes.isDisjoint(with: Self.reallocationFilters)
    }

    /// True when the Odometer bucket is active — either explicitly via `.odometer` ("All
    /// Vehicles"), or implicitly via a specific vehicle narrowing, which (like an income/expense
    /// subtype) marks the bucket active without the parent filter also being present.
    private var hasOdometerFilter: Bool {
        selectedTransactionTypes.contains(.odometer) || selectedVehicleFilter != nil
    }

    /// Whether each section should show: either nothing has been narrowed at all (default
    /// selection = show everything), or this bucket specifically has an active filter. Buckets
    /// combine additively — selecting Income doesn't hide Reallocations or Odometer, it just
    /// adds Income alongside whatever else is already selected. Reallocations aren't tied to
    /// any category, so narrowing to a specific category hides that section entirely (Odometer
    /// readings do have categories, so that section instead filters its contents — see
    /// `monthOdometerReadings`/`totalsMilesDriven` — rather than hiding).
    private var showsIncomeOrExpense: Bool { selectedTransactionTypes.isDefaultSelection || hasIncomeOrExpenseFilter }
    private var showsReallocations: Bool {
        selectedTransactionCategories.isEmpty && (selectedTransactionTypes.isDefaultSelection || hasReallocationFilter)
    }
    private var showsOdometer: Bool { selectedTransactionTypes.isDefaultSelection || hasOdometerFilter }

    // MARK: - Filtered Summary Totals (react to the active type/category filter and day selection)

    /// Incomes for the current day selection only (no type/category filter applied yet).
    private var dayFilteredIncomes: [Income] {
        guard !selectedDays.isEmpty else { return precomputedData.expandedIncomes }
        return selectedDays.sorted().flatMap { incomesForDay($0) }
    }

    /// Expenses for the current day selection only (no type/category filter applied yet).
    private var dayFilteredExpenses: [Expense] {
        guard !selectedDays.isEmpty else { return precomputedData.expandedExpenses }
        return selectedDays.sorted().flatMap { expensesForDay($0) }
    }

    private func matchesTypeFilter(income: Income) -> Bool {
        guard !selectedTransactionTypes.isDefaultSelection else { return true }
        if selectedTransactionTypes.contains(.income) { return true }
        if selectedTransactionTypes.contains(.otherIncome) && !income.isTaxable { return true }
        if selectedTransactionTypes.contains(.taxableIncome) && income.isTaxable { return true }
        if selectedTransactionTypes.contains(.recurringIncome) && income.isRecurring { return true }
        if selectedTransactionTypes.contains(.oneTimeIncome) && !income.isRecurring { return true }
        return false
    }

    private func matchesTypeFilter(expense: Expense) -> Bool {
        guard !selectedTransactionTypes.isDefaultSelection else { return true }
        if selectedTransactionTypes.contains(.expenses) { return true }
        if selectedTransactionTypes.contains(.recurringExpenses) && expense.isRecurring && !expense.isMonthlyPaymentPlan { return true }
        if selectedTransactionTypes.contains(.paymentPlans) && expense.isMonthlyPaymentPlan { return true }
        if selectedTransactionTypes.contains(.oneTimeExpense) && !expense.isRecurring && !expense.isMonthlyPaymentPlan { return true }
        return false
    }

    private func matchesCategoryFilter(_ categories: [String]) -> Bool {
        guard !selectedTransactionCategories.isEmpty else { return true }
        if selectedTransactionCategories.contains(SettingsDefault.uncategorizedSentinel) {
            return categories.isEmpty || categories.contains(SettingsDefault.uncategorizedSentinel)
        }
        return categories.contains(where: { selectedTransactionCategories.contains($0) })
    }

    /// Incomes reflected in the summary totals: day selection + type filter + category filter
    /// applied, emptied out entirely when no income/expense-related filter is active (mirrors
    /// the combined transactions section being hidden in that case).
    private var totalsIncomes: [Income] {
        guard showsIncomeOrExpense else { return [] }
        return dayFilteredIncomes.filter { matchesTypeFilter(income: $0) && matchesCategoryFilter($0.categories) }
    }

    /// Expenses reflected in the summary totals — same rules as `totalsIncomes`.
    private var totalsExpenses: [Expense] {
        guard showsIncomeOrExpense else { return [] }
        return dayFilteredExpenses.filter { matchesTypeFilter(expense: $0) && matchesCategoryFilter($0.categories) }
    }

    /// Reallocations reflected in the summary totals. Reallocations aren't tied to specific
    /// days, so a day selection zeroes them out here too — mirroring the Reallocations section
    /// itself being hidden whenever days are selected or no reallocation-related filter is active.
    private var totalsReallocations: [Reallocation] {
        guard selectedDays.isEmpty, showsReallocations else { return [] }
        return activeMonthReallocations ?? precomputedData.sortedActiveReallocations
    }

    /// Income/expense/reallocation/Total Excess-Needed totals for the summary section, recomputed
    /// from the filtered sets above. Equivalent to `precomputedData`'s full-month totals when no
    /// filter or day selection is active.
    private var filteredHeaderTotals: MonthHeaderTotals {
        computeHeaderTotals(incomes: totalsIncomes, expenses: totalsExpenses, reallocations: totalsReallocations,
                            isTaxSavingsEnabled: item.isTaxSavingsEnabled, taxSavingsPercentage: item.taxSavingsPercentage)
    }

    /// Miles driven this month — zeroed out when a day is selected or no odometer-related
    /// filter is active; scoped to just the selected vehicle when one is chosen, otherwise
    /// summed across every vehicle. When a category filter is active, sums each matching
    /// reading's own precomputed delta instead of the per-vehicle total, since a category
    /// may only match some of a vehicle's readings for the month.
    private var totalsMilesDriven: Int {
        guard selectedDays.isEmpty, showsOdometer else { return 0 }
        guard selectedTransactionCategories.isEmpty else {
            return monthOdometerReadings.reduce(0) { $0 + (precomputedData.milesDrivenByReadingID[$1.id] ?? 0) }
        }
        if let vehicle = selectedVehicleFilter {
            return precomputedData.milesDrivenByVehicle[vehicle] ?? 0
        }
        return precomputedData.milesDrivenByVehicle.values.reduce(0, +)
    }

    /// Odometer readings dated in this month, filtered to the selected vehicle and/or category
    /// when set.
    private var monthOdometerReadings: [OdometerReading] {
        let vehicleFiltered: [OdometerReading]
        if let vehicle = selectedVehicleFilter {
            vehicleFiltered = precomputedData.activeOdometerReadings.filter { $0.vehicle == vehicle }
        } else {
            vehicleFiltered = precomputedData.activeOdometerReadings
        }
        return vehicleFiltered.filter { matchesCategoryFilter($0.categories) }
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
        List {
            // Calendar Section
            Section {
                makeCustomCalendarView()
                    .id("calendarSection-\(yearMonth.year)-\(yearMonth.month)")
                    .onAppear {
                        guard scrollToCalendarOnAppear else { return }
                        onScrollToCalendarTriggered?()
                        let scrollID = "calendarSection-\(yearMonth.year)-\(yearMonth.month)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                                proxy.scrollTo(scrollID, anchor: .center)
                            }
                        }
                    }
                } header: {
                    HStack {
                        HStack(spacing: 6) {
                            Menu {
                                Picker(selection: Binding(
                                    get: { yearMonth.month },
                                    set: { newMonth in onJumpToMonth(YearMonth(year: yearMonth.year, month: newMonth)) }
                                )) {
                                    ForEach(1...12, id: \.self) { month in
                                        Text(monthDisplayName(month)).tag(month)
                                    }
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            } label: {
                                Text(yearMonth.displayName)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                            Menu {
                                Picker(selection: Binding(
                                    get: { yearMonth.year },
                                    set: { newYear in onJumpToMonth(YearMonth(year: newYear, month: yearMonth.month)) }
                                )) {
                                    ForEach(yearRange.reversed(), id: \.self) { year in
                                        Text(String(year)).tag(year)
                                    }
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            } label: {
                                Text(String(yearMonth.year))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                        }
                        Spacer()
                    }
                }

                // Summary Section (Income + Expenses + Reallocations + Needed/Excess Income)
                // Computed once per pass from `filteredHeaderTotals` so all four rows react
                // together to the active type/category filter and any selected calendar days.
                Section {
                    let totals = filteredHeaderTotals
                    Button {
                        selectedVehicleFilter = nil
                        if selectedTransactionTypes == [.income] {
                            selectedTransactionTypes = .defaultSelection
                        } else {
                            selectedTransactionTypes = [.income]
                        }
                    } label: {
                        HStack {
                            Text("Income")
                                .fontWeight(.medium)
                            Spacer()
                            Text(totals.incomeTotal, format: .currency(code: selectedCurrency.code))
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        selectedVehicleFilter = nil
                        if selectedTransactionTypes == [.expenses] {
                            selectedTransactionTypes = .defaultSelection
                        } else {
                            selectedTransactionTypes = [.expenses]
                        }
                    } label: {
                        HStack {
                            Text("Expenses")
                                .fontWeight(.medium)
                            Spacer()
                            HStack(spacing: 8) {
                                if item.isTaxSavingsEnabled {
                                    Text(totals.taxTotal, format: .currency(code: selectedCurrency.code))
                                        .foregroundStyle(.orange)
                                        .fontWeight(.medium)
                                    Text("/")
                                        .foregroundStyle(.primary)
                                        .offset(y: -1)
                                }
                                Text(totals.expenseTotal, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.red)
                                    .fontWeight(.medium)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        selectedVehicleFilter = nil
                        if selectedTransactionTypes == [.reallocations] {
                            selectedTransactionTypes = .defaultSelection
                        } else {
                            selectedTransactionTypes = [.reallocations]
                        }
                    } label: {
                        HStack {
                            Text("Reallocations")
                                .fontWeight(.medium)
                            Spacer()
                            HStack(spacing: 8) {
                                Text(totals.reallocationInTotal, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.green)
                                    .fontWeight(.medium)
                                Text("/")
                                    .foregroundStyle(.primary)
                                    .offset(y: -1)
                                Text(totals.reallocationOutTotal, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.red)
                                    .fontWeight(.medium)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Text(totals.remaining.isEffectivelyPositive ? "Total Excess" : "Total Needed")
                            .fontWeight(.medium)
                        Spacer()
                        if totals.remaining.isEffectivelyPositive {
                            Text(totals.remaining, format: .currency(code: selectedCurrency.code))
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        } else if totals.remaining.isEffectivelyZero {
                            Text(0.0, format: .currency(code: selectedCurrency.code))
                                .foregroundStyle(.indigo)
                                .fontWeight(.medium)
                        } else {
                            HStack(spacing: 4) {
                                Text(totals.breakEven, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.indigo)
                                    .fontWeight(.medium)
                                if item.isTaxSavingsEnabled {
                                    Text("/")
                                        .foregroundStyle(.primary)
                                        .offset(y: -1)
                                    Text(totals.incomeNeeded, format: .currency(code: selectedCurrency.code))
                                        .foregroundStyle(.indigo)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }

                    Button {
                        selectedVehicleFilter = nil
                        if selectedTransactionTypes == [.odometer] {
                            selectedTransactionTypes = .defaultSelection
                        } else {
                            selectedTransactionTypes = [.odometer]
                        }
                    } label: {
                        HStack {
                            Text("Miles Driven")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(totalsMilesDriven) mi")
                                .foregroundStyle(.primary)
                                .fontWeight(.medium)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Combined Transactions Section
                if showsIncomeOrExpense {
                Section {
                    let filteredIncomes: [Income] = {
                        if !selectedDays.isEmpty {
                            return selectedDays.sorted().flatMap { incomesForDay($0) }
                        } else {
                            return precomputedData.expandedIncomes
                        }
                    }()

                    let filteredExpenses: [Expense] = {
                        if !selectedDays.isEmpty {
                            return selectedDays.sorted().flatMap { expensesForDay($0) }
                        } else {
                            return precomputedData.expandedExpenses
                        }
                    }()

                    // Income + expense list only; reallocations appear in their own section below.
                    let sortedTransactions: [TransactionItem] = {
                        if selectedDays.isEmpty {
                            return precomputedData.sortedBaseTransactions.filter {
                                if case .reallocation = $0 { return false }
                                return true
                            }
                        }
                        let all: [TransactionItem] =
                            filteredIncomes.map { TransactionItem.income($0, adjustedDate: $0.date) } +
                            filteredExpenses.map { TransactionItem.expense($0, adjustedDate: $0.date) }
                        return all.sorted {
                            if $0.sortDate != $1.sortDate { return $0.sortDate < $1.sortDate }
                            return $0.createdAt < $1.createdAt
                        }
                    }()

                    let typeFiltered: [TransactionItem] = {
                        guard !selectedTransactionTypes.isDefaultSelection else { return sortedTransactions }
                        return sortedTransactions.filter { transaction in
                            switch transaction {
                            case .income(let i, _):
                                if selectedTransactionTypes.contains(.income) { return true }
                                if selectedTransactionTypes.contains(.otherIncome) && !i.isTaxable { return true }
                                if selectedTransactionTypes.contains(.taxableIncome) && i.isTaxable { return true }
                                if selectedTransactionTypes.contains(.recurringIncome) && i.isRecurring { return true }
                                if selectedTransactionTypes.contains(.oneTimeIncome) && !i.isRecurring { return true }
                                return false
                            case .expense(let e, _):
                                if selectedTransactionTypes.contains(.expenses) { return true }
                                if selectedTransactionTypes.contains(.recurringExpenses) && e.isRecurring && !e.isMonthlyPaymentPlan { return true }
                                if selectedTransactionTypes.contains(.paymentPlans) && e.isMonthlyPaymentPlan { return true }
                                if selectedTransactionTypes.contains(.oneTimeExpense) && !e.isRecurring && !e.isMonthlyPaymentPlan { return true }
                                return false
                            case .reallocation: return false
                            }
                        }
                    }()

                    let displayedTransactions: [TransactionItem] = selectedTransactionCategories.isEmpty ? typeFiltered : typeFiltered.filter { t in
                        switch t {
                        case .income(let i, _): return selectedTransactionCategories.contains(SettingsDefault.uncategorizedSentinel) ? (i.categories.isEmpty || i.categories.contains(SettingsDefault.uncategorizedSentinel)) : i.categories.contains(where: { selectedTransactionCategories.contains($0) })
                        case .expense(let e, _): return selectedTransactionCategories.contains(SettingsDefault.uncategorizedSentinel) ? (e.categories.isEmpty || e.categories.contains(SettingsDefault.uncategorizedSentinel)) : e.categories.contains(where: { selectedTransactionCategories.contains($0) })
                        case .reallocation: return false
                        }
                    }

                    // Unfiltered (no day selection): reuse the precomputed dict built off the main
                    // actor. Day-filtered: recompute over just that day's incomes — a small,
                    // user-initiated slice, not worth precomputing for every possible day combination.
                    let distributedTaxes: [UUID: Decimal] = selectedDays.isEmpty
                        ? precomputedData.distributedTaxes
                        : (item.isTaxSavingsEnabled
                            ? TaxDistributionHelper.distributedTaxAmounts(
                                for: filteredIncomes.map { (income: $0, amount: $0.amount) },
                                defaultPercentage: item.taxSavingsPercentage
                            )
                            : [:])

                    if displayedTransactions.isEmpty {
                        Text("No transactions added")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(displayedTransactions) { transaction in
                            switch transaction {
                            case .income(let income, _):
                                IncomeRowView(
                                    income: income,
                                    isReordering: false,
                                    isSelected: selectedIncomes.contains(OccurrenceKey(id: income.id, date: income.date)),
                                    dateFormat: dateFormat,
                                    selectedCurrency: selectedCurrency,
                                    highlightColor: highlightColor,
                                    taxSavingsPercentage: item.taxSavingsPercentage,
                                    isTaxSavingsEnabled: item.isTaxSavingsEnabled,
                                    distributedTaxAmount: distributedTaxes[income.id],
                                    onToggleSelection: { selectedIncomes.toggle(OccurrenceKey(id: income.id, date: income.date)) },
                                    onEdit: {
                                        onEditIncome(income, income.date)
                                    },
                                    onDuplicate: {
                                        onDuplicateIncome(income, income.date)
                                    },
                                    onDelete: {
                                        onDeleteIncome(income)
                                    }
                                )
                            case .expense(let expense, let adjustedDate):
                                makeExpenseListRow(expense: expense, adjustedDate: adjustedDate)
                            case .reallocation(let reallocation):
                                reallocationRow(for: reallocation)
                            }
                        }
                    }
                }
                }

                // Reallocations Section (always below transactions, hidden when day filter active)
                if selectedDays.isEmpty && showsReallocations {
                    let monthReallocs = activeMonthReallocations ?? []
                    Section {
                        if monthReallocs.isEmpty {
                            Text("No Reallocations Added")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(monthReallocs) { reallocation in
                                reallocationRow(for: reallocation)
                            }
                        }
                    }
                }

                // Odometer Section (unlabeled, below Reallocations, hidden when day filter active
                // or no odometer-related filter is active). Combines additively with the other
                // buckets — e.g. selecting Income doesn't hide this, only narrowing away from
                // Odometer specifically (or picking Income from the default state) does.
                if selectedDays.isEmpty && showsOdometer {
                    Section {
                        if monthOdometerReadings.isEmpty {
                            Text("No Odometer Readings Added")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(monthOdometerReadings) { reading in
                                odometerReadingRow(for: reading)
                                    .id(reading.id.uuidString)
                            }
                        }
                    }
                }

                // Attachments Section (only when no days are selected and no filter is active).
                // A vehicle selection always takes `selectedTransactionTypes` out of its default
                // state (see `selectVehicle`), so no separate vehicle check is needed here.
                if selectedDays.isEmpty && selectedTransactionTypes.isDefaultSelection && selectedTransactionCategories.isEmpty {
                    MonthAttachmentsSection(
                        attachments: monthAttachmentsBinding,
                        attachmentToView: Binding(
                            get: { nil },
                            set: { if let a = $0 { onViewAttachment(a) } }
                        ),
                        selectedAttachments: $selectedAttachments,
                        highlightColor: highlightColor,
                        onToggleSelection: { attachment in
                            selectedAttachments.toggle(attachment.id)
                        }
                    )
                }
            }
            .listRowSpacing(0)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .onReceive(NotificationCenter.default.publisher(for: .scrollToNewItem)) { notification in
                withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                    if let scrollID = notification.object as? String {
                        proxy.scrollTo(scrollID, anchor: .center)
                    } else if let uuid = notification.object as? UUID {
                        proxy.scrollTo(uuid, anchor: .center)
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                if !newValue {
                    proxy.scrollTo("calendarSection-\(yearMonth.year)-\(yearMonth.month)", anchor: .center)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollPageToTop)) { _ in
                guard isActive else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                    proxy.scrollTo("calendarSection-\(yearMonth.year)-\(yearMonth.month)", anchor: .center)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollPageToFirstSection)) { _ in
                guard isActive else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                    proxy.scrollTo("calendarSection-\(yearMonth.year)-\(yearMonth.month)", anchor: .center)
                }
            }
        }
    }

    // MARK: - Calendar View

    @ViewBuilder
    private func makeCustomCalendarView() -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let allWeekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]
        let weekStartIdx = item.effectiveCalendarWeekStartDay - 1
        let orderedWeekdayLetters = (0..<7).map { allWeekdayLetters[(weekStartIdx + $0) % 7] }

        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(orderedWeekdayLetters.enumerated()), id: \.offset) { _, letter in
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .frame(width: 38, height: 38)
                            Text(letter)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(Color.clear).frame(width: 6, height: 6)
                            if item.isTaxSavingsEnabled {
                                Circle().fill(Color.clear).frame(width: 6, height: 6)
                            }
                            Circle().fill(Color.clear).frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
            }

            calendarGridCanvas
                .overlay(
                    CalendarDragOverlay(
                        calendarDays: flattenedCalendarDays.map { $0.day },
                        onToggleDay: { day in
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                    )
                )
        }
        .padding(.horizontal, -7)
        .padding(.vertical, 1)
    }

    // MARK: - Calendar Canvas

    /// Renders the day grid as a single Canvas draw call, replacing the old 42-cell LazyVGrid.
    /// Reduces ~300 SwiftUI view nodes to 1, cutting initial layout cost during swipe-in.
    private var calendarGridCanvas: some View {
        let numRows = precomputedData.calendarWeeks.count
        let isTaxEnabled = item.isTaxSavingsEnabled
        let now = Date()
        let isCurrentMonth = yearMonth.year == now.year && yearMonth.month == now.month
        let todayDay = isCurrentMonth ? Calendar.current.component(.day, from: now) : -1

        return Canvas { ctx, size in
            let cellW = size.width / 7
            // Each grid row is 50pt tall with 3pt spacing beneath it.
            let rowStride = CGFloat(53)
            // Circle geometry: 38pt diameter, centered at top of cell + 19pt.
            let circleR = CGFloat(19)
            // Dot geometry: 6pt diameter, centre-to-centre spacing = 9pt (6 + 3 gap).
            let dotR = CGFloat(3)
            let dotStep = CGFloat(9)

            for flatItem in precomputedData.flatCalendarDays {
                guard let day = flatItem.day else { continue }
                let col = flatItem.offset % 7
                let row = flatItem.offset / 7
                let cx = CGFloat(col) * cellW + cellW * 0.5
                let cy = CGFloat(row) * rowStride + circleR

                let isSelected = selectedDays.contains(day)
                let isToday = day == todayDay

                // Background circle
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - circleR, y: cy - circleR,
                                           width: circleR * 2, height: circleR * 2)),
                    with: .color(isSelected ? highlightColor : Color(uiColor: .tertiarySystemFill))
                )

                // Day-number text
                let textFg: Color = isSelected ? Color(uiColor: .systemBackground)
                                               : (isToday ? highlightColor : .primary)
                let weight: Font.Weight = (isSelected || isToday) ? .bold : .medium
                ctx.draw(
                    Text("\(day)").font(.body.weight(weight)).foregroundStyle(textFg),
                    at: CGPoint(x: cx, y: cy), anchor: .center
                )

                // Activity dots — centres at dotY, horizontally centred under circle
                let dotY = CGFloat(row) * rowStride + 45.0
                let dayIncs = precomputedData.incomesByDay[day, default: []]
                let hasIncomeActivity = !dayIncs.isEmpty
                let hasExpenseActivity = !precomputedData.expensesByDay[day, default: []].isEmpty

                if isTaxEnabled {
                    // 3 dots: income · tax · expense  (total width 24pt, first centre at cx-9)
                    let hasTaxable = dayIncs.contains { $0.isTaxable }
                    let colors: [Color] = [
                        hasIncomeActivity ? .green : Color(uiColor: .systemGray4),
                        hasTaxable        ? .orange : Color(uiColor: .systemGray4),
                        hasExpenseActivity ? .red : Color(uiColor: .systemGray4)
                    ]
                    for (i, c) in colors.enumerated() {
                        let dx = cx - dotStep + CGFloat(i) * dotStep
                        ctx.fill(Path(ellipseIn: CGRect(x: dx - dotR, y: dotY - dotR,
                                                        width: dotR * 2, height: dotR * 2)),
                                 with: .color(c))
                    }
                } else {
                    // 2 dots: income · expense  (total width 15pt, first centre at cx-4.5)
                    let colors: [Color] = [
                        hasIncomeActivity  ? .green : Color(uiColor: .systemGray4),
                        hasExpenseActivity ? .red   : Color(uiColor: .systemGray4)
                    ]
                    for (i, c) in colors.enumerated() {
                        let dx = cx - dotStep * 0.5 + CGFloat(i) * dotStep
                        ctx.fill(Path(ellipseIn: CGRect(x: dx - dotR, y: dotY - dotR,
                                                        width: dotR * 2, height: dotR * 2)),
                                 with: .color(c))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(numRows) * 53)
    }

    // MARK: - Calendar Helpers

    private var flattenedCalendarDays: [(offset: Int, day: Int?)] {
        precomputedData.flatCalendarDays
    }

    // O(1) day lookups using the pre-built per-day index in precomputedData.
    private func incomesForDay(_ day: Int) -> [Income] {
        precomputedData.incomesByDay[day] ?? []
    }

    private func expensesForDay(_ day: Int) -> [Expense] {
        precomputedData.expensesByDay[day] ?? []
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func reallocationRow(for reallocation: Reallocation) -> some View {
        let linkedDate = reallocations.first(where: { $0.id == reallocation.linkedId })?.date ?? reallocation.date
        HighlightableReallocationRow(
            reallocation: reallocation,
            linkedDate: linkedDate,
            isSelected: selectedReallocations.contains(reallocation.id),
            highlightColor: highlightColor,
            dateFormat: dateFormat,
            selectedCurrency: selectedCurrency,
            onToggleSelection: { selectedReallocations.toggle(reallocation.id) },
            onEdit: { onEditReallocation(reallocation) },
            onDelete: { onDeleteReallocation(reallocation) }
        )
    }

    @ViewBuilder
    private func odometerReadingRow(for reading: OdometerReading) -> some View {
        HighlightableOdometerReadingRow(
            reading: reading,
            dateFormat: dateFormat,
            vehicleMilesDriven: precomputedData.milesDrivenByReadingID[reading.id] ?? 0,
            onTap: { onEditOdometerReading(reading) },
            onDelete: { onDeleteOdometerReading(reading) }
        )
    }

    @ViewBuilder
    private func makeExpenseListRow(expense: Expense, adjustedDate: Date) -> some View {
        let key = "\(expense.id.uuidString)-\(expense.date.timeIntervalSince1970)"
        let displayDate = precomputedData.expenseDisplayDates[key] ?? expense.date
        ExpenseListRow(
            expense: expense,
            displayDate: displayDate,
            dateFormat: dateFormat,
            selectedCurrency: selectedCurrency,
            highlightColor: highlightColor,
            isSelected: selectedExpenses.contains(OccurrenceKey(id: expense.id, date: expense.date)),
            canReimburse: !incomes.contains(where: { $0.id == expense.reimbursedByIncomeId }),
            onToggleSelection: { selectedExpenses.toggle(OccurrenceKey(id: expense.id, date: expense.date)) },
            onEdit: { onEditExpense(expense, adjustedDate) },
            onDuplicate: { onDuplicateExpense(expense, adjustedDate) },
            onPayOff: { onPayOffExpense(expense) },
            onDelete: { onDeleteExpense(expense) }
        )
    }

}

// MARK: - MonthPageView Equatable

/// Equality is defined over the inputs that actually affect rendering. Closures (callbacks) are
/// intentionally excluded — they are always new instances each parent body pass but are
/// functionally identical, so excluding them lets .equatable() skip re-renders during swipes.
/// @Bindable `item` changes are handled by SwiftUI's observation system independently.
/// precomputedData.calendarWeeks.isEmpty detects the empty→populated transition: when the
/// background cache task fills in a month that previously held .empty data, the calendar weeks
/// go from [] to a real grid, making the instances unequal and triggering a re-render.
/// Selection mode is intentionally NOT compared here — it's read via `@Environment(\.selectionMode)`
/// by the individual row views instead, so toggling it invalidates only those rows (via
/// @Observable property tracking) rather than this view's whole body (calendar, totals, filtering).
extension MonthPageView: Equatable {
    static func == (lhs: MonthPageView, rhs: MonthPageView) -> Bool {
        lhs.yearMonth == rhs.yearMonth
        && lhs.dataVersion == rhs.dataVersion
        && lhs.renderVersion == rhs.renderVersion
        && lhs.isActive == rhs.isActive
        && lhs.precomputedData.calendarWeeks.isEmpty == rhs.precomputedData.calendarWeeks.isEmpty
    }
}

// MARK: - Transaction Item

/// Unified transaction item for the chronological list, wrapping income/expense/reallocation occurrences.
nonisolated enum TransactionItem: Identifiable {
    case income(Income, adjustedDate: Date)
    case expense(Expense, adjustedDate: Date)
    case reallocation(Reallocation)

    var id: String {
        switch self {
        case .income(let income, let adjustedDate):
            return "\(income.id.uuidString)-\(adjustedDate.timeIntervalSince1970)"
        case .expense(let expense, let adjustedDate):
            return "\(expense.id.uuidString)-\(adjustedDate.timeIntervalSince1970)"
        case .reallocation(let reallocation):
            return reallocation.id.uuidString
        }
    }

    var sortDate: Date {
        switch self {
        case .income(_, let adjustedDate): return adjustedDate
        case .expense(_, let adjustedDate): return adjustedDate
        case .reallocation(let reallocation): return reallocation.date
        }
    }

    var createdAt: Date {
        switch self {
        case .income(let income, _): return income.createdAt
        case .expense(let expense, _): return expense.createdAt
        case .reallocation(let reallocation): return reallocation.createdAt
        }
    }
}

// MARK: - Highlightable Row Views

struct HighlightableExpenseRow: View {
    let expense: Expense
    let displayDate: Date
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    /// Days left before permanent deletion; rendered as a red "• N Days" suffix. Trash-only.
    var trashDaysLeft: Int? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                HStack(spacing: 4) {
                    Text(displayDate, format: dateFormat.style)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    if expense.isMonthlyPaymentPlan || expense.isRecurring {
                        Text("• \(expense.effectiveFrequency)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    if let trashDaysLeft {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(trashDaysLeft > 0 ? "\(trashDaysLeft) Day\(trashDaysLeft == 1 ? "" : "s")" : "Today")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if expense.isMonthlyPaymentPlan, let total = expense.totalAmount {
                    Text(expense.amount, format: .currency(code: selectedCurrency.code))
                        .foregroundStyle(.red)
                    HStack(spacing: 4) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(total, format: .currency(code: selectedCurrency.code))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                } else {
                    Text(expense.amount, format: .currency(code: selectedCurrency.code))
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

/// Wraps `HighlightableExpenseRow` with selection/tap/context-menu behavior. Reads selection
/// mode from `@Environment(\.selectionMode)` directly (rather than taking it as a parameter) so
/// toggling selection invalidates only mounted rows, not MonthPageView's whole body.
struct ExpenseListRow: View {
    let expense: Expense
    let displayDate: Date
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let highlightColor: Color
    let isSelected: Bool
    let canReimburse: Bool
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onPayOff: () -> Void
    let onDelete: () -> Void

    @Environment(\.selectionMode) private var selectionMode
    private var isSelecting: Bool { selectionMode.isSelecting }

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }
            HighlightableExpenseRow(
                expense: expense,
                displayDate: displayDate,
                dateFormat: dateFormat,
                selectedCurrency: selectedCurrency
            )
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelection()
            } else {
                onEdit()
            }
        }
        .contextMenu {
            if !isSelecting {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(.primary)
                if canReimburse {
                    Button(action: onPayOff) {
                        Label("Reimburse", systemImage: "arrow.uturn.left.circle")
                    }
                    .tint(.primary)
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
        .tint(nil)
    }
}

struct HighlightableReallocationRow: View {
    let reallocation: Reallocation
    let linkedDate: Date
    let isSelected: Bool
    let highlightColor: Color
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.selectionMode) private var selectionMode
    private var isSelecting: Bool { selectionMode.isSelecting }

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }
            innerContent()
                .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelection()
            } else {
                onEdit()
            }
        }
        .contextMenu {
            if !isSelecting {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .tint(nil)
    }

    @ViewBuilder
    private func innerContent() -> some View {
        let toFromPrefix = reallocation.isFromEntry ? "To" : "From"
        let amount = reallocation.signedAmount
        let absAmount = abs(amount)

        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reallocation")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                HStack(spacing: 4) {
                    Text(reallocation.date, format: dateFormat.monthYearStyle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Text("• \(toFromPrefix) \(linkedDate.formatted(dateFormat.monthYearStyle))")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            Text(absAmount.formatted(.currency(code: selectedCurrency.code)))
                .foregroundStyle(amount.isEffectivelyZero || amount.isEffectivelyPositive ? .green : .red)
        }
    }
}

struct HighlightableOdometerReadingRow: View {
    let reading: OdometerReading
    let dateFormat: DateFormat
    /// This reading's own delta from the reading immediately before it (same vehicle), shown
    /// beneath the odometer value. 0 for a vehicle's very first reading ever.
    let vehicleMilesDriven: Int
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.vehicle)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                Text(reading.date, format: dateFormat.style)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(reading.odometerValue) mi")
                    .foregroundStyle(Color.primary)
                Text("\(vehicleMilesDriven) mi driven")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .tint(nil)
    }
}

/// Thin wrapper around `BudgetAttachmentManagementView` that reads selection mode from
/// `@Environment(\.selectionMode)` directly, isolating that dependency to this small view
/// instead of MonthPageView's whole body. `BudgetAttachmentManagementView` keeps its own
/// explicit `isSelecting` parameter since it's also used elsewhere with independent selection state.
struct MonthAttachmentsSection: View {
    @Binding var attachments: [BudgetAttachment]
    @Binding var attachmentToView: BudgetAttachment?
    @Binding var selectedAttachments: Set<UUID>
    let highlightColor: Color
    let onToggleSelection: (BudgetAttachment) -> Void

    @Environment(\.selectionMode) private var selectionMode

    var body: some View {
        BudgetAttachmentManagementView(
            attachments: $attachments,
            attachmentToView: $attachmentToView,
            alwaysShow: true,
            isSelecting: selectionMode.isSelecting,
            selectedAttachments: $selectedAttachments,
            highlightColor: highlightColor,
            onToggleSelection: onToggleSelection
        )
    }
}

