//
//  MonthDetailsPageView.swift
//  Bookee
//
//  Sheet view showing all transactions for a specific month, with a calendar
//  day picker, editing support, and attachment management.
//

import SwiftUI
import UIKit
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Month Details Sheet View

private struct CalendarDragOverlay: UIViewRepresentable {
    let calendarDays: [Int?]
    let onToggleDay: (Int) -> Void
    let onClearSelection: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        context.coordinator.panGesture = pan
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.calendarDays = calendarDays
        context.coordinator.onToggleDay = onToggleDay
        context.coordinator.onClearSelection = onClearSelection
        guard !context.coordinator.didSetupScrollView else { return }
        DispatchQueue.main.async {
            var next: UIResponder? = uiView.next
            while let r = next {
                if let sv = r as? UIScrollView {
                    sv.panGestureRecognizer.require(toFail: context.coordinator.panGesture)
                    context.coordinator.didSetupScrollView = true
                    break
                }
                next = r.next
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var calendarDays: [Int?] = []
        var onToggleDay: ((Int) -> Void)?
        var onClearSelection: (() -> Void)?
        var panGesture: UIPanGestureRecognizer!
        var didSetupScrollView = false
        private var lastDay: Int? = nil
        private var lastTapDate: Date? = nil

        private func day(at point: CGPoint, viewWidth: CGFloat) -> Int? {
            // Each row is 44pt tall + 6pt spacing = 50pt stride
            let col = Int(point.x * 7 / (viewWidth + 6))
            let row = Int(point.y / 50)
            guard col >= 0, col < 7, row >= 0 else { return nil }
            let index = row * 7 + col
            guard index >= 0, index < calendarDays.count else { return nil }
            return calendarDays[index]
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            switch g.state {
            case .began, .changed:
                let pt = g.location(in: view)
                let d = day(at: pt, viewWidth: view.bounds.width)
                if d != lastDay {
                    lastDay = d
                    if let d { onToggleDay?(d) }
                }
            case .ended, .cancelled, .failed:
                lastDay = nil
            default: break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            let pt = g.location(in: view)
            guard let d = day(at: pt, viewWidth: view.bounds.width) else { return }
            let now = Date()
            if let prev = lastTapDate, now.timeIntervalSince(prev) < 0.4 {
                lastTapDate = nil
                onClearSelection?()
            } else {
                lastTapDate = now
                onToggleDay?(d)
            }
        }
    }
}

// MARK: - Filter Options Sheet

private struct FilterOptionsSheet: View {
    @Binding var transactionFilter: MonthDetailsPageView.TransactionFilter
    @Binding var selectedCategories: Set<String>
    @Bindable var item: Item
    let highlightColor: Color
    let month: Int
    let year: Int
    @Environment(\.modelContext) private var modelContext
    @AppStorage("transactionCategories") private var storedCategories: String = "[]"
    @AppStorage("showFooters") private var showFooters: Bool = true
    @State private var localCategories: [String] = []
    @State private var localHiddenCategories: [String] = []
    @State private var categoryToEdit: String = ""
    @State private var editCategoryName: String = ""
    @State private var showingEditAlert = false
    @State private var newCategoryName: String = ""
    @State private var showingAddAlert = false
    @State private var showingHiddenCategories = false
    @State private var showingDeleteConfirmation = false
    @State private var categoryToDelete: String? = nil
    @Environment(\.dismiss) private var dismiss

    private var visibleCategories: [String] {
        localCategories.filter { !localHiddenCategories.contains($0) }
    }

    private var categoryCounts: [String: Int] {
        buildCategoryCounts(for: item, month: month, year: year)
    }

    @ViewBuilder private var categoriesSection: some View {
        Section {
                Button {
                    selectedCategories = []
                } label: {
                    HStack {
                        Text("All")
                            .foregroundStyle(.primary)
                        Text("\(categoryCounts.values.reduce(0, +))")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        if selectedCategories.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(highlightColor)
                        }
                    }
                }

                ForEach(visibleCategories, id: \.self) { category in
                    Button {
                        selectedCategories.remove(SettingsDefault.uncategorizedSentinel)
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    } label: {
                        HStack {
                            Text(category)
                                .foregroundStyle(.primary)
                            Text("\(categoryCounts[category, default: 0])")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if selectedCategories.contains(category) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(highlightColor)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            hideCategory(category)
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                        .tint(.gray)
                        Button {
                            categoryToEdit = category
                            editCategoryName = category
                            showingEditAlert = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            categoryToDelete = category
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button {
                            categoryToEdit = category
                            editCategoryName = category
                            showingEditAlert = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.primary)
                        Button {
                            hideCategory(category)
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        Divider()
                        Button(role: .destructive) {
                            categoryToDelete = category
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
                .onMove { from, to in
                    var visible = visibleCategories
                    visible.move(fromOffsets: from, toOffset: to)
                    let hiddenSet = Set(localHiddenCategories)
                    var result: [String] = []
                    var visIdx = 0
                    for cat in localCategories {
                        if hiddenSet.contains(cat) {
                            result.append(cat)
                        } else {
                            result.append(visible[visIdx])
                            visIdx += 1
                        }
                    }
                    localCategories = result
                    storedCategories = localCategories.asAppStorageString
                }

                Button {
                    if selectedCategories == [SettingsDefault.uncategorizedSentinel] {
                        selectedCategories = []
                    } else {
                        selectedCategories = [SettingsDefault.uncategorizedSentinel]
                    }
                } label: {
                    HStack {
                        Text("Uncategorized")
                            .foregroundStyle(.primary)
                        Text("\(categoryCounts[SettingsDefault.uncategorizedSentinel, default: 0])")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        if selectedCategories == [SettingsDefault.uncategorizedSentinel] {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(highlightColor)
                        }
                    }
                }
            } header: {
                Text("Categories")
            } footer: {
                if showFooters && !visibleCategories.isEmpty {
                    Text("Swipe right on a category to edit or hide it, or left to delete it.")
                }
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    ForEach(MonthDetailsPageView.TransactionFilter.allCases, id: \.self) { filter in
                        Button {
                            if filter != .all && transactionFilter == filter {
                                transactionFilter = .all
                            } else {
                                transactionFilter = filter
                            }
                        } label: {
                            HStack {
                                Text(filter.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if transactionFilter == filter {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(highlightColor)
                                }
                            }
                        }
                    }
                }

                categoriesSection

            }
            .tint(.primary)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .tint(.primary)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingHiddenCategories = true
                    } label: {
                        Label("Hidden", systemImage: "eye.slash")
                    }
                    .tint(.primary)
                    Spacer()
                    Button {
                        newCategoryName = ""
                        showingAddAlert = true
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                    .tint(.primary)
                }
            }
            .navigationDestination(isPresented: $showingHiddenCategories) {
                HiddenCategoriesPage(localHiddenCategories: $localHiddenCategories, item: item, month: month, year: year)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            localCategories = storedCategories.asCategories
            localHiddenCategories = item.hiddenFilterCategories?.asCategories ?? []
        }
        .onChange(of: storedCategories) { _, newValue in
            let updated = newValue.asCategories
            if updated != localCategories { localCategories = updated }
        }
        .onChange(of: item.hiddenFilterCategories) { _, newValue in
            localHiddenCategories = newValue?.asCategories ?? []
            modelContext.saveWithLogging("month details filter")
        }
        .tint(.primary)
        .categoryManagementAlerts(
            newCategoryName: $newCategoryName,
            showingAddAlert: $showingAddAlert,
            onAdd: addCategory,
            editCategoryName: $editCategoryName,
            showingEditAlert: $showingEditAlert,
            onRename: { renameCategory(from: categoryToEdit, to: editCategoryName) },
            categoryToDelete: $categoryToDelete,
            showingDeleteConfirmation: $showingDeleteConfirmation,
            onDelete: { if let cat = categoryToDelete { deleteCategory(cat) } }
        )
    }

    private func hideCategory(_ category: String) {
        selectedCategories.remove(category)
        if !localHiddenCategories.contains(category) {
            localHiddenCategories.append(category)
            item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        }
    }

    private func unhideCategory(_ category: String) {
        localHiddenCategories.removeAll { $0 == category }
        item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty else { return }
        var cats = storedCategories.asCategories
        if !cats.contains(trimmed) {
            cats.append(trimmed)
            storedCategories = cats.asAppStorageString
        }
        newCategoryName = ""
    }

    private func deleteCategory(_ category: String) {
        var cats = storedCategories.asCategories
        cats.removeAll { $0 == category }
        storedCategories = cats.asAppStorageString
        selectedCategories.remove(category)
        localHiddenCategories.removeAll { $0 == category }
        item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
    }

    private func renameCategory(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty, trimmed != old else { return }
        var cats = storedCategories.asCategories
        if let index = cats.firstIndex(of: old) {
            cats[index] = trimmed
            storedCategories = cats.asAppStorageString
        }
        if selectedCategories.contains(old) {
            selectedCategories.remove(old)
            selectedCategories.insert(trimmed)
        }
        if let idx = localHiddenCategories.firstIndex(of: old) {
            localHiddenCategories[idx] = trimmed
            item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        }
        updateItemsForRenamedCategory(from: old, to: trimmed, modelContext: modelContext)
        NotificationCenter.default.post(
            name: .categoryRenamed,
            object: nil,
            userInfo: ["oldName": old, "newName": trimmed]
        )
    }
}

/// Sheet view that displays detailed breakdown of all transactions for a specific month
/// Shows incomes, expenses, reallocations, and attachments with calendar day picker
/// Supports filtering by specific day and full editing/management of all items
struct MonthDetailsPageView: View {
    let yearMonth: YearMonth
    @State private var monthOffset: Int = 0
    @Bindable var item: Item
    @State private var expenses: [Expense] = []
    @State private var incomes: [Income] = []
    @State private var attachments: [BudgetAttachment] = []
    @State private var reallocations: [Reallocation] = []
    @State private var isSelecting = false
    @State private var selectedExpenses = Set<OccurrenceKey>()
    @State private var selectedIncomes = Set<OccurrenceKey>()
    @State private var selectedReallocations = Set<UUID>()
    @State private var selectedAttachments = Set<UUID>()
    @State private var isInitialLoad = true

    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true
    
    private var currentYearMonth: YearMonth {
        guard monthOffset != 0 else { return yearMonth }
        let cal = Calendar.current
        let comps = DateComponents(year: yearMonth.year, month: yearMonth.month)
        guard let base = cal.date(from: comps),
              let shifted = cal.date(byAdding: .month, value: monthOffset, to: base) else { return yearMonth }
        return YearMonth(year: cal.component(.year, from: shifted), month: cal.component(.month, from: shifted))
    }

    private enum MonthRelation { case current, past, future }

    private var monthRelation: MonthRelation {
        let now = Date()
        if currentYearMonth.year == now.year && currentYearMonth.month == now.month { return .current }
        if currentYearMonth.year < now.year || (currentYearMonth.year == now.year && currentYearMonth.month < now.month) { return .past }
        return .future
    }

    /// Returns the default day for new items: today for current month, last day for past, 1 for future.
    private var defaultDayForMonth: Int {
        switch monthRelation {
        case .current: return Date().day
        case .past:
            let comps = DateComponents(year: currentYearMonth.year, month: currentYearMonth.month + 1, day: 1)
            if let next = Calendar.current.date(from: comps),
               let last = Calendar.current.date(byAdding: .day, value: -1, to: next) {
                return last.day
            }
            return 28
        case .future: return 1
        }
    }

    /// Returns the default date+time for new items: now for current month, 23:59 last day for past, 00:00 first day for future.
    private var defaultDateForMonth: Date {
        switch monthRelation {
        case .current: return Date()
        case .past:
            let comps = DateComponents(year: currentYearMonth.year, month: currentYearMonth.month + 1,
                                       day: 1, hour: 0, minute: 0, second: 0)
            if let next = Calendar.current.date(from: comps),
               let last = Calendar.current.date(byAdding: .minute, value: -1, to: next) { return last }
            return Calendar.current.date(from: DateComponents(year: currentYearMonth.year, month: currentYearMonth.month,
                                                               day: 28, hour: 23, minute: 59, second: 0)) ?? Date()
        case .future:
            return Calendar.current.date(from: DateComponents(year: currentYearMonth.year, month: currentYearMonth.month,
                                                               day: 1, hour: 0, minute: 0, second: 0)) ?? Date()
        }
    }
    
    @State private var selectedDays: Set<Int> = []
    
    // Transaction filter state
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case income = "Income"
        case expenses = "Expenses"
        case reallocations = "Reallocations"
    }
    @State private var transactionFilter: TransactionFilter = .all

    // Category filter state
    @AppStorage("transactionCategories") private var storedCategories: String = "[]"
    @State private var selectedCategories: Set<String> = []

    // Local state for sub-sheet presentations
    @State private var localExpenseToEdit: Expense?
    @State private var localIncomeToEdit: Income?
    @State private var attachmentToView: BudgetAttachment?
    @State private var reallocationToEdit: Reallocation?
    @State private var expenseOccurrenceDate: Date?
    @State private var incomeOccurrenceDate: Date?
    
    // States for add item sheets
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingReallocateFunds = false
    @State private var showingIncomeView = false
    @State private var showingFilterSheet = false
    @State private var goToCurrentMonthTrigger = false

    @State private var expenseCountBeforeAdd = 0
    @State private var incomeCountBeforeAdd = 0
    @State private var reallocationCountBeforeAdd = 0

    // Attachment picker states
    @State private var showingBudgetPhotoPicker = false
    @State private var showingBudgetFilePicker = false
    
    // Delete confirmation state
    @State private var showingDeleteConfirmation = false
    @State private var expenseToDelete: Expense?
    @State private var incomeToDelete: Income?
    @State private var reallocationToDelete: Reallocation?
    
    // Recurring deletion scope
    @State private var showingRecurringScopeAlert = false
    @State private var pendingRecurringScope: RecurringScope?
    
    // Recurring duplication scope
    @State private var showingRecurringDuplicateScopeAlert = false
    @State private var expenseToDuplicate: Expense?
    @State private var incomeToDuplicate: Income?
    @State private var expenseAdjustedDate: Date?
    @State private var incomeAdjustedDate: Date?
    
    // Unified transaction type for chronological list
    /// Uniquely identifies a single occurrence of an item (recurring items share a UUID but have distinct dates).
    struct OccurrenceKey: Hashable {
        let id: UUID
        let date: Date
    }

    enum TransactionItem: Identifiable {
        case income(Income, adjustedDate: Date)
        case expense(Expense, adjustedDate: Date)
        case reallocation(Reallocation)
        
        var id: String {
            switch self {
            case .income(let income, let adjustedDate): 
                // Use a combination of ID and date to make each occurrence unique
                return "\(income.id.uuidString)-\(adjustedDate.timeIntervalSince1970)"
            case .expense(let expense, let adjustedDate): 
                // Use a combination of ID and date to make each occurrence unique
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
    
    /// Check if a recurring expense has multiple occurrences across all months
    // Filter attachments to only show those for this month, sorted by creation time (oldest first)
    private var monthAttachments: [BudgetAttachment] {
        attachments.filter { $0.month == currentYearMonth.month && $0.year == currentYearMonth.year }
    }
    
    // Binding for month-specific attachments
    private var monthAttachmentsBinding: Binding<[BudgetAttachment]> {
        Binding(
            get: { monthAttachments },
            set: { newValue in
                // Remove old attachments for this month
                attachments.removeAll { $0.month == currentYearMonth.month && $0.year == currentYearMonth.year }
                // Add new attachments
                attachments.append(contentsOf: newValue)
            }
        )
    }
    
    private var monthIncomes: [Income] {
        incomes.filter { income in
            (income.date.year == currentYearMonth.year && income.date.month == currentYearMonth.month)
            || (income.isRecurring && isItemActiveInMonth(date: income.date, endDate: income.endDate, targetMonth: currentYearMonth.month, targetYear: currentYearMonth.year, frequency: income.recurringFrequency.rawValue, rule: income.resolvedRule))
        }
    }

    private var monthExpenses: [Expense] {
        expenses.filter { expense in
            (expense.date.year == currentYearMonth.year && expense.date.month == currentYearMonth.month)
            || ((expense.isRecurring || expense.isMonthlyPaymentPlan) && isItemActiveInMonth(date: expense.date, endDate: expense.endDate, targetMonth: currentYearMonth.month, targetYear: currentYearMonth.year, frequency: expense.effectiveFrequency, rule: expense.resolvedRule))
        }
    }



    /// Reallocations for the current month, optionally filtered to the selected days.
    private var dayFilteredReallocations: [Reallocation] {
        selectedDays.isEmpty
            ? reallocations.activeIn(yearMonth: currentYearMonth)
            : selectedDays.sorted().flatMap { reallocationsForDay($0) }
    }

    private var totalIncome: Double {
        guard transactionFilter == .all || transactionFilter == .income else { return 0.0 }
        var items = selectedDays.isEmpty ? expandedMonthIncomes() : selectedDays.sorted().flatMap { incomesForDay($0) }
        if !selectedCategories.isEmpty {
            items = items.filter { selectedCategories.contains(SettingsDefault.uncategorizedSentinel) ? ($0.categories.isEmpty || $0.categories.contains(SettingsDefault.uncategorizedSentinel)) : $0.categories.contains(where: { selectedCategories.contains($0) }) }
        }
        var total = items.map { $0.amount }.sumMoney()
        if transactionFilter == .all && selectedCategories.isEmpty {
            total = roundMoney(total + dayFilteredReallocations.filter { !$0.isFromEntry }.map { $0.amount }.sumMoney())
        }
        return total
    }

    private var totalExpenses: Double {
        guard transactionFilter == .all || transactionFilter == .expenses else { return 0.0 }
        var items = selectedDays.isEmpty ? expandedMonthExpenses() : selectedDays.sorted().flatMap { expensesForDay($0) }
        if !selectedCategories.isEmpty {
            items = items.filter { selectedCategories.contains(SettingsDefault.uncategorizedSentinel) ? ($0.categories.isEmpty || $0.categories.contains(SettingsDefault.uncategorizedSentinel)) : $0.categories.contains(where: { selectedCategories.contains($0) }) }
        }
        var total = items.map { $0.amount }.sumMoney()
        if transactionFilter == .all && selectedCategories.isEmpty {
            total = roundMoney(total + dayFilteredReallocations.filter { $0.isFromEntry }.map { $0.amount }.sumMoney())
        }
        return total
    }
    
    private var totalTaxSavings: Double {
        // Only show tax savings when filter is .all or .income
        guard transactionFilter == .all || transactionFilter == .income else { return 0.0 }
        
        // Only calculate tax savings when viewing the full month (not a specific day)
        // and when tax savings is enabled
        guard selectedDays.isEmpty, item.isTaxSavingsEnabled else { return 0.0 }
        
        // Calculate tax on taxable income only - use expanded incomes to count all occurrences
        let taxableIncome = expandedMonthIncomes().filter { $0.isTaxable }.map { $0.amount }.sumMoney()
        let taxAmount = roundMoney(taxableIncome * item.taxRate)
        
        return taxAmount
    }
    
    /// Tax amount for the income filter header — respects day and category filters.
    private var incomeTaxForHeader: Double {
        guard transactionFilter == .income, item.isTaxSavingsEnabled else { return 0.0 }
        var items = selectedDays.isEmpty ? expandedMonthIncomes() : selectedDays.sorted().flatMap { incomesForDay($0) }
        if !selectedCategories.isEmpty {
            items = items.filter { selectedCategories.contains(SettingsDefault.uncategorizedSentinel) ? ($0.categories.isEmpty || $0.categories.contains(SettingsDefault.uncategorizedSentinel)) : $0.categories.contains(where: { selectedCategories.contains($0) }) }
        }
        let taxableIncome = items.filter { $0.isTaxable }.map { $0.amount }.sumMoney()
        return roundMoney(taxableIncome * item.taxRate)
    }
    
    // Computed properties for reallocation totals when filter is set to reallocations
    private var activeMonthReallocations: [Reallocation]? {
        guard transactionFilter == .reallocations, selectedDays.isEmpty else { return nil }
        return reallocations.activeIn(yearMonth: currentYearMonth)
    }

    private var totalReallocationIn: Double {
        guard let r = activeMonthReallocations else { return 0.0 }
        return r.filter { !$0.isFromEntry }.map { $0.amount }.sumMoney()
    }
    
    private var totalReallocationOut: Double {
        guard let r = activeMonthReallocations else { return 0.0 }
        return r.filter { $0.isFromEntry }.map { $0.amount }.sumMoney()
    }

    // MARK: - Calendar Header Budget Metrics

    private var calendarMonthTaxableIncome: Double {
        guard item.isTaxSavingsEnabled else { return 0.0 }
        return expandedMonthIncomes().filter { $0.isTaxable }.map { $0.amount }.sumMoney()
    }

    private var calendarMonthUntaxableIncome: Double {
        item.isTaxSavingsEnabled
            ? expandedMonthIncomes().filter { !$0.isTaxable }.map { $0.amount }.sumMoney()
            : expandedMonthIncomes().map { $0.amount }.sumMoney()
    }

    private var calendarMonthExpenses: Double {
        expandedMonthExpenses().map { $0.amount }.sumMoney()
    }

    private var calendarPositiveReallocations: Double {
        reallocations.additionsIn(yearMonth: currentYearMonth).map { $0.amount }.sumMoney()
    }

    private var calendarNegativeReallocations: Double {
        reallocations.deductionsIn(yearMonth: currentYearMonth).map { $0.amount }.sumMoney()
    }

    private var calendarHeaderRemaining: Double {
        let reallocated = reallocations.activeIn(yearMonth: currentYearMonth).map { $0.signedAmount }.sumMoney()
        let taxSavings = item.isTaxActive ? roundMoney(calendarMonthTaxableIncome * item.taxRate) : 0.0
        var raw = roundMoney(calendarMonthUntaxableIncome + calendarMonthTaxableIncome)
        if item.isTaxActive { raw = roundMoney(raw - taxSavings) }
        raw = roundMoney(raw - calendarMonthExpenses)
        raw = roundMoney(raw + reallocated)
        return raw.roundedAndNormalizedMoney()
    }

    private var calendarHeaderBreakEven: Double {
        let totalUntaxable = roundMoney(calendarMonthUntaxableIncome + calendarPositiveReallocations)
        let effectiveExpenses = roundMoney(calendarMonthExpenses + calendarNegativeReallocations)
        if item.isTaxActive {
            let taxOnCurrent = roundMoney(calendarMonthTaxableIncome * item.taxRate)
            let afterTax = roundMoney(calendarMonthTaxableIncome - taxOnCurrent)
            let available = roundMoney(afterTax + totalUntaxable)
            return max(0, roundMoney(effectiveExpenses - available))
        } else {
            let totalIncome = roundMoney(calendarMonthTaxableIncome + totalUntaxable)
            return max(0, roundMoney(effectiveExpenses - totalIncome))
        }
    }

    private var calendarHeaderIncomeNeeded: Double {
        let totalUntaxable = roundMoney(calendarMonthUntaxableIncome + calendarPositiveReallocations)
        let effectiveExpenses = roundMoney(calendarMonthExpenses + calendarNegativeReallocations)
        let covered = roundMoney(min(effectiveExpenses, totalUntaxable))
        let remaining = roundMoney(max(0, effectiveExpenses - covered))
        let divisor = 1.0 - item.taxRate
        let needed = divisor.isEffectivelyZero ? remaining : roundMoney(remaining / divisor)
        let s1 = roundMoney(covered + needed)
        let s2 = roundMoney(s1 - calendarMonthUntaxableIncome)
        let s3 = roundMoney(s2 - calendarPositiveReallocations)
        return max(0, roundMoney(s3 - calendarMonthTaxableIncome))
    }

    private func clearDuplicateState() {
        expenseToDuplicate = nil
        incomeToDuplicate = nil
        expenseAdjustedDate = nil
        incomeAdjustedDate = nil
    }

    private func performDuplicate(scope: RecurringScope) {
        pendingRecurringScope = scope
        if let expense = expenseToDuplicate, let adjustedDate = expenseAdjustedDate {
            copyExpense(expense, adjustedDate: adjustedDate)
        } else if let income = incomeToDuplicate, let adjustedDate = incomeAdjustedDate {
            copyIncome(income, adjustedDate: adjustedDate)
        }
        clearDuplicateState()
    }

    private func copyRecurringItem<T: RecurringItem>(_ item: T, adjustedDate: Date?, into array: inout [T], onCurrentOnly: ((inout T) -> Void)? = nil) {
        let startDate = adjustedDate ?? item.date
        guard let scope = pendingRecurringScope else {
            var copy = item.duplicate(); copy.date = startDate
            array.append(copy)
            return
        }
        switch scope {
        case .currentOnly:
            var copy = item.duplicate()
            copy.date = startDate; copy.endDate = nil; copy.showEndDate = false
            copy.isRecurring = false
            onCurrentOnly?(&copy)
            array.append(copy)
        case .currentAndFuture:
            var copy = item.duplicate(); copy.date = startDate
            array.append(copy)
        case .all:
            array.append(item.duplicate())
        }
        pendingRecurringScope = nil
    }

    private func copyExpense(_ expense: Expense, adjustedDate: Date? = nil) {
        copyRecurringItem(expense, adjustedDate: adjustedDate, into: &expenses) { $0.isMonthlyPaymentPlan = false }
    }

    private func payOffExpense(_ expense: Expense) {
        incomes.append(makeIncomeFromExpense(expense))
    }

    private func copyIncome(_ income: Income, adjustedDate: Date? = nil) {
        copyRecurringItem(income, adjustedDate: adjustedDate, into: &incomes)
    }
    
    private func removeIncome(_ income: Income) {
        applyRecurringItemDeletion(item: income, items: &incomes, pendingScope: &pendingRecurringScope)
    }

    private func removeExpense(_ expense: Expense) {
        applyRecurringItemDeletion(item: expense, items: &expenses, pendingScope: &pendingRecurringScope)
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedExpenses.removeAll()
        selectedIncomes.removeAll()
        selectedReallocations.removeAll()
        selectedAttachments.removeAll()
    }

    private func goToCurrentMonth(proxy: ScrollViewProxy) {
        stopDeceleratingScrollViews()
        let now = Date()
        let alreadyCurrent = currentYearMonth.year == now.year && currentYearMonth.month == now.month
        monthOffset = (now.year - yearMonth.year) * 12 + (now.month - yearMonth.month)
        // Always explicitly update viewedYearMonth so BudgetVisualizerPageView switches to
        // the current year when the user pops back — even if monthOffset didn't change
        // (which happens after force-close restoration when the saved yearMonth already
        // equals the current month, preventing onChange(of: monthOffset) from firing).
        let targetYearMonth = YearMonth(year: now.year, month: now.month)
        NavigationStateManager.shared.saveCurrentYearMonth(targetYearMonth)
        NavigationStateManager.shared.viewedYearMonth = targetYearMonth
        if !alreadyCurrent {
            selectedDays.removeAll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo("calendarSection", anchor: .center) }
        }
    }

    private func stopDeceleratingScrollViews() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }
        stopScrollViews(in: window)
    }

    private func stopScrollViews(in view: UIView) {
        if let sv = view as? UIScrollView, sv.isDecelerating || sv.isDragging {
            sv.setContentOffset(sv.contentOffset, animated: false)
        }
        for subview in view.subviews {
            stopScrollViews(in: subview)
        }
    }

    private func toggleExpenseSelectionState(for expense: Expense) {
        selectedExpenses.toggle(OccurrenceKey(id: expense.id, date: expense.date))
    }

    private func toggleIncomeSelectionState(for income: Income) {
        selectedIncomes.toggle(OccurrenceKey(id: income.id, date: income.date))
    }
    
    private func toggleReallocationSelectionState(for reallocation: Reallocation) {
        selectedReallocations.toggle(reallocation.id)
    }
    
    private func toggleAttachmentSelectionState(for attachment: BudgetAttachment) {
        selectedAttachments.toggle(attachment.id)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
        List {
            // Calendar Section
                Section {
                    makeCustomCalendarView()
                } header: {
                    HStack {
                        Text("Calendar")
                        Spacer()
                        if calendarHeaderRemaining.isEffectivelyPositive {
                            Text(calendarHeaderRemaining, format: .currency(code: selectedCurrency.code))
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        } else if calendarHeaderRemaining.isEffectivelyZero {
                            Text(0.0, format: .currency(code: selectedCurrency.code))
                                .foregroundStyle(.indigo)
                                .fontWeight(.medium)
                        } else {
                            HStack(spacing: 4) {
                                Text(calendarHeaderBreakEven, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.indigo)
                                    .fontWeight(.medium)
                                if item.isTaxSavingsEnabled {
                                    Text("/")
                                        .foregroundStyle(.primary)
                                    Text(calendarHeaderIncomeNeeded, format: .currency(code: selectedCurrency.code))
                                        .foregroundStyle(.indigo)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                    .textCase(nil)
                } footer: {
                    if showFooters {
                        Text("Tap or drag finger over days to select/deselect them, or double tap any day to deselect all.")
                    }
                }
                .id("calendarSection")

                // Combined Transactions Section (Income, Expenses, Reallocations)
                Section {
                    // Filter by selected day if a day is selected
                    let filteredIncomes: [Income] = {
                        if !selectedDays.isEmpty {
                            return selectedDays.sorted().flatMap { incomesForDay($0) }
                        } else {
                            return expandedMonthIncomes()
                        }
                    }()
                    
                    let filteredExpenses: [Expense] = {
                        if !selectedDays.isEmpty {
                            return selectedDays.sorted().flatMap { expensesForDay($0) }
                        } else {
                            return expandedMonthExpenses()
                        }
                    }()
                    
                    let monthReallocations: [Reallocation] = {
                        let calendar = Calendar.current
                        
                        // Filter reallocations for this month
                        let monthFiltered = reallocations.activeIn(yearMonth: currentYearMonth)
                        
                        // If specific days are selected, filter by those days
                        if !selectedDays.isEmpty {
                            return monthFiltered.filter { reallocation in
                                let reallocationDay = calendar.component(.day, from: reallocation.date)
                                return selectedDays.contains(reallocationDay)
                            }
                        } else {
                            return monthFiltered
                        }
                    }()
                    
                    // Combine all items into unified transaction list with adjusted dates for proper sorting
                    let allTransactions: [TransactionItem] = 
                        filteredIncomes.map { income in
                            // For expanded recurring items, the date is already adjusted
                            // For regular items from a selected day, the date should also be correct
                            // Just use the income's date as-is since expandedMonthIncomes() already set it correctly
                            return TransactionItem.income(income, adjustedDate: income.date)
                        } +
                        filteredExpenses.map { expense in
                            // For expanded recurring items, the date is already adjusted
                            // For regular items from a selected day, the date should also be correct
                            return TransactionItem.expense(expense, adjustedDate: expense.date)
                        } +
                        monthReallocations.map { TransactionItem.reallocation($0) }
                    
                    // Sort chronologically by date and time, then by creation time
                    let sortedTransactions = allTransactions.sorted { item1, item2 in
                        if item1.sortDate != item2.sortDate {
                            return item1.sortDate < item2.sortDate
                        } else {
                            // Same date and time: sort by creation time (oldest first)
                            return item1.createdAt < item2.createdAt
                        }
                    }
                    
                    // Filter transactions based on type and category filters
                    let typeFiltered: [TransactionItem] = {
                        switch transactionFilter {
                        case .all:
                            return sortedTransactions
                        case .income:
                            return sortedTransactions.filter { if case .income = $0 { return true } else { return false } }
                        case .expenses:
                            return sortedTransactions.filter { if case .expense = $0 { return true } else { return false } }
                        case .reallocations:
                            return sortedTransactions.filter { if case .reallocation = $0 { return true } else { return false } }
                        }
                    }()
                    let displayedTransactions: [TransactionItem] = selectedCategories.isEmpty ? typeFiltered : typeFiltered.filter { t in
                        switch t {
                        case .income(let i, _): return selectedCategories.contains(SettingsDefault.uncategorizedSentinel) ? (i.categories.isEmpty || i.categories.contains(SettingsDefault.uncategorizedSentinel)) : i.categories.contains(where: { selectedCategories.contains($0) })
                        case .expense(let e, _): return selectedCategories.contains(SettingsDefault.uncategorizedSentinel) ? (e.categories.isEmpty || e.categories.contains(SettingsDefault.uncategorizedSentinel)) : e.categories.contains(where: { selectedCategories.contains($0) })
                        case .reallocation: return false
                        }
                    }
                    
                    // Calculate distributed tax amounts for incomes
                    let distributedTaxes = TaxDistributionHelper.distributedTaxAmounts(
                        for: filteredIncomes.sorted { income1, income2 in
                            // Sort by full date and time
                            if income1.date != income2.date {
                                return income1.date < income2.date
                            } else {
                                return income1.createdAt < income2.createdAt
                            }
                        },
                        taxRate: item.taxRate
                    )
                    
                    if displayedTransactions.isEmpty {
                        // Show placeholder when no transactions
                        Text("No transactions added")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(displayedTransactions) { transaction in
                            switch transaction {
                            case .income(let income, let adjustedDate):
                                // Create a display income with the adjusted date
                                let displayIncome = Income(
                                    id: income.id,
                                    name: income.name,
                                    amount: income.amount,
                                    date: adjustedDate,
                                    showDate: income.showDate,
                                    endDate: income.endDate,
                                    showEndDate: income.showEndDate,
                                    isRecurring: income.isRecurring,
                                    recurringFrequency: income.recurringFrequency,
                                    attachments: income.attachments,
                                    isTaxable: income.isTaxable
                                )
                                
                                IncomeRowView(
                                    income: displayIncome,
                                    isSelecting: isSelecting,
                                    isReordering: false,
                                    isSelected: selectedIncomes.contains(OccurrenceKey(id: income.id, date: income.date)),
                                    dateFormat: dateFormat,
                                    selectedCurrency: selectedCurrency,
                                    highlightColor: highlightColor,
                                    taxSavingsPercentage: item.taxSavingsPercentage,
                                    isTaxSavingsEnabled: item.isTaxSavingsEnabled,
                                    distributedTaxAmount: distributedTaxes[income.id],
                                    onToggleSelection: { toggleIncomeSelectionState(for: income) },
                                    onEdit: { 
                                        incomeOccurrenceDate = adjustedDate
                                        localIncomeToEdit = income
                                    },
                                    onDuplicate: { 
                                        incomeToDuplicate = income
                                        incomeAdjustedDate = adjustedDate
                                        // For recurring items, always show scope selection
                                        if income.isRecurring {
                                            showingRecurringDuplicateScopeAlert = true
                                        } else {
                                            pendingRecurringScope = nil
                                            copyIncome(income, adjustedDate: adjustedDate)
                                            incomeToDuplicate = nil
                                            incomeAdjustedDate = nil
                                        }
                                    },
                                    onDelete: { 
                                        incomeToDelete = income
                                        // For recurring items, always show scope selection
                                        if income.isRecurring {
                                            showingRecurringScopeAlert = true
                                        } else {
                                            pendingRecurringScope = nil
                                            showingDeleteConfirmation = true
                                        }
                                    }
                                )
                            case .expense(let expense, let adjustedDate):
                                HStack(spacing: 0) {
                                    if isSelecting {
                                        SelectionIndicator(isSelected: selectedExpenses.contains(OccurrenceKey(id: expense.id, date: expense.date)), highlightColor: highlightColor)
                                            .padding(.trailing, 12)
                                    }
                                    
                                    makeExpenseRowContent(for: expense)
                                    .contentShape(Rectangle())
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelecting {
                                        toggleExpenseSelectionState(for: expense)
                                    } else {
                                        expenseOccurrenceDate = adjustedDate
                                        localExpenseToEdit = expense
                                    }
                                }
                                .if(!isSelecting) { view in
                                    view
                                        .contextMenu {
                                            Button {
                                                expenseToDuplicate = expense
                                                expenseAdjustedDate = adjustedDate
                                                // For payment plans, always duplicate all items
                                                if expense.isMonthlyPaymentPlan {
                                                    pendingRecurringScope = .all
                                                    copyExpense(expense, adjustedDate: adjustedDate)
                                                    expenseToDuplicate = nil
                                                    expenseAdjustedDate = nil
                                                }
                                                // For recurring items, always show scope selection
                                                else if expense.isRecurring {
                                                    showingRecurringDuplicateScopeAlert = true
                                                } else {
                                                    pendingRecurringScope = nil
                                                    copyExpense(expense, adjustedDate: adjustedDate)
                                                    expenseToDuplicate = nil
                                                    expenseAdjustedDate = nil
                                                }
                                            } label: {
                                                Label("Duplicate", systemImage: "plus.square.on.square")
                                            }
                                            
                                            Button {
                                                payOffExpense(expense)
                                            } label: {
                                                Label("Pay Off", systemImage: "banknote")
                                            }
                                            
                                            Divider()
                                            
                                            Button(role: .destructive) {
                                                expenseToDelete = expense
                                                // For payment plans, always delete all items
                                                if expense.isMonthlyPaymentPlan {
                                                    pendingRecurringScope = .all
                                                    showingDeleteConfirmation = true
                                                }
                                                // For recurring items, always show scope selection
                                                else if expense.isRecurring {
                                                    showingRecurringScopeAlert = true
                                                } else {
                                                    pendingRecurringScope = nil
                                                    showingDeleteConfirmation = true
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .tint(nil)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button {
                                                expenseToDelete = expense
                                                if expense.isMonthlyPaymentPlan {
                                                    pendingRecurringScope = .all
                                                    showingDeleteConfirmation = true
                                                } else if expense.isRecurring {
                                                    showingRecurringScopeAlert = true
                                                } else {
                                                    pendingRecurringScope = nil
                                                    showingDeleteConfirmation = true
                                                }
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .tint(.red)
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                expenseToDuplicate = expense
                                                expenseAdjustedDate = adjustedDate
                                                if expense.isMonthlyPaymentPlan {
                                                    pendingRecurringScope = .all
                                                    copyExpense(expense, adjustedDate: adjustedDate)
                                                    expenseToDuplicate = nil
                                                    expenseAdjustedDate = nil
                                                } else if expense.isRecurring {
                                                    showingRecurringDuplicateScopeAlert = true
                                                } else {
                                                    pendingRecurringScope = nil
                                                    copyExpense(expense, adjustedDate: adjustedDate)
                                                    expenseToDuplicate = nil
                                                    expenseAdjustedDate = nil
                                                }
                                            } label: {
                                                Image(systemName: "plus.square.on.square")
                                            }
                                            .tint(.blue)
                                            Button {
                                                payOffExpense(expense)
                                            } label: {
                                                Image(systemName: "banknote")
                                            }
                                            .tint(.green)
                                        }
                                }
                            case .reallocation(let reallocation):
                                reallocationRow(for: reallocation)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(transactionFilter == .all ? "Transactions" : transactionFilter.rawValue)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            // Show amounts based on filter (always display, even when zero)
                            switch transactionFilter {
                            case .all:
                                // Show total income (green)
                                Text(totalIncome, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.green)
                                    .fontWeight(.medium)
                                
                                Text("/")
                                    .foregroundStyle(.secondary)
                                
                                // Show total expenses (red)
                                Text(totalExpenses, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.red)
                                    .fontWeight(.medium)
                                
                            case .income:
                                // Show only income (green)
                                Text(totalIncome, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.green)
                                    .fontWeight(.medium)
                                
                                if item.isTaxSavingsEnabled {
                                    Text("/")
                                        .foregroundStyle(.secondary)
                                    
                                    Text(incomeTaxForHeader, format: .currency(code: selectedCurrency.code))
                                        .foregroundStyle(.orange)
                                        .fontWeight(.medium)
                                }
                                
                            case .expenses:
                                // Show only expenses (red)
                                Text(totalExpenses, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.red)
                                    .fontWeight(.medium)
                                
                            case .reallocations:
                                // Show reallocations in (green) and out (red)
                                Text(totalReallocationIn, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.green)
                                    .fontWeight(.medium)
                                
                                Text("/")
                                    .foregroundStyle(.secondary)
                                
                                Text(totalReallocationOut, format: .currency(code: selectedCurrency.code))
                                    .foregroundStyle(.red)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .textCase(nil)
                } footer: {
                    if showFooters {
                        Text("Swipe right on a transaction to duplicate it or pay it off (expenses only), or left to delete it. Tap one to edit it.")
                    }
                }
                // Only show Attachments section when no days are selected
                if selectedDays.isEmpty {
                    
                    // Attachments Section
                    BudgetAttachmentManagementView(
                        attachments: monthAttachmentsBinding,
                        attachmentToView: $attachmentToView,
                        alwaysShow: true,
                        isSelecting: isSelecting,
                        selectedAttachments: $selectedAttachments,
                        highlightColor: highlightColor,
                        onToggleSelection: { attachment in
                            toggleAttachmentSelectionState(for: attachment)
                        }
                    )
                }
            }
            .listRowSpacing(0)
            .navigationTitle("\(currentYearMonth.displayName) Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelecting {
                        Button {
                            exitSelectionMode()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.primary)
                    } else {
                        let monthReallocations = reallocations.activeIn(yearMonth: currentYearMonth)
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select", systemImage: "checklist")
                        }
                        .tint(.primary)
                        .disabled(monthIncomes.isEmpty && monthExpenses.isEmpty && monthReallocations.isEmpty && monthAttachments.isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if isSelecting {
                        let monthReallocations = reallocations.activeIn(yearMonth: currentYearMonth)
                        let allExpandedIncomes = expandedMonthIncomes()
                        let allExpandedExpenses = expandedMonthExpenses()
                        let totalItems = allExpandedIncomes.count + allExpandedExpenses.count + monthReallocations.count + monthAttachments.count
                        let totalSelected = allExpandedIncomes.filter { selectedIncomes.contains(OccurrenceKey(id: $0.id, date: $0.date)) }.count +
                                           allExpandedExpenses.filter { selectedExpenses.contains(OccurrenceKey(id: $0.id, date: $0.date)) }.count +
                                           monthReallocations.filter { selectedReallocations.contains($0.id) }.count +
                                           monthAttachments.filter { selectedAttachments.contains($0.id) }.count
                        let selectAllText = totalSelected == 0 ? "Select All" : (totalSelected == totalItems ? "Deselect All" : "Select All")
                        let hasSelection = !selectedExpenses.isEmpty || !selectedIncomes.isEmpty || !selectedReallocations.isEmpty || !selectedAttachments.isEmpty
                        Spacer()

                        Button {
                            if totalSelected == totalItems {
                                allExpandedIncomes.forEach { selectedIncomes.remove(OccurrenceKey(id: $0.id, date: $0.date)) }
                                allExpandedExpenses.forEach { selectedExpenses.remove(OccurrenceKey(id: $0.id, date: $0.date)) }
                                monthReallocations.forEach { selectedReallocations.remove($0.id) }
                                monthAttachments.forEach { selectedAttachments.remove($0.id) }
                            } else {
                                allExpandedIncomes.forEach { selectedIncomes.insert(OccurrenceKey(id: $0.id, date: $0.date)) }
                                allExpandedExpenses.forEach { selectedExpenses.insert(OccurrenceKey(id: $0.id, date: $0.date)) }
                                monthReallocations.forEach { selectedReallocations.insert($0.id) }
                                monthAttachments.forEach { selectedAttachments.insert($0.id) }
                            }
                        } label: {
                            Label(selectAllText, systemImage: totalSelected == totalItems ? "checklist.unchecked" : "checklist.checked")
                        }
                        .tint(.primary)
                        
                        Button(role: .destructive) {
                            guard hasSelection else { return }
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    } else {
                        Button {
                            goToCurrentMonthTrigger.toggle()
                        } label: {
                            Label("Current Month", systemImage: "calendar.badge.clock")
                        }
                        .tint(.primary)

                        Button {
                            showingIncomeView = true
                        } label: {
                            Label("Year Overview", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .tint(.primary)

                        Button {
                            showingFilterSheet = true
                        } label: {
                            Label(transactionFilter.rawValue, systemImage: "line.3.horizontal.decrease")
                        }
                        .tint(!selectedCategories.isEmpty || transactionFilter != .all ? highlightColor : .primary)

                        Spacer()

                        Button {
                            monthOffset -= 1
                            selectedDays.removeAll()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .tint(.primary)

                        Button {
                            monthOffset += 1
                            selectedDays.removeAll()
                        } label: {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .tint(.primary)

                        Spacer()
                        
                        Menu {
                            Button {
                                showingReallocateFunds = true
                            } label: {
                                Label("Reallocate Funds", systemImage: "arrow.left.arrow.right")
                            }
                            
                            Button {
                                showingAddExpense = true
                            } label: {
                                Label("Expense", systemImage: "cart")
                            }
                            
                            Button {
                                showingAddIncome = true
                            } label: {
                                Label("Income", systemImage: "dollarsign.circle")
                            }
                            
                            Button {
                                showingBudgetPhotoPicker = true
                            } label: {
                                Label("Photo", systemImage: "photo")
                            }
                            
                            Button {
                                showingBudgetFilePicker = true
                            } label: {
                                Label("File", systemImage: "doc")
                            }
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                        .tint(.primary)
                    }
                }
            }
        .onAppear {
            isInitialLoad = true
            loadBudgetData()
        }
        .onBudgetDataChange(
            expenses: expenses, incomes: incomes,
            attachments: attachments, reallocations: reallocations,
            isInitialLoad: isInitialLoad, persist: { persistBudgetData() }
        )
        .onChange(of: monthOffset) { _, _ in
            NavigationStateManager.shared.saveCurrentYearMonth(currentYearMonth)
            NavigationStateManager.shared.viewedYearMonth = currentYearMonth
        }
        .onChange(of: goToCurrentMonthTrigger) { _, newValue in
            guard newValue else { return }
            goToCurrentMonth(proxy: proxy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                goToCurrentMonthTrigger = false
            }
        }
        .onChange(of: showingAddExpense) { old, new in
            if !old && new {
                expenseCountBeforeAdd = expenses.count
            } else if old && !new {
                if expenses.count > expenseCountBeforeAdd,
                   let newest = expenses.max(by: { $0.createdAt < $1.createdAt }) {
                    let targetID = "\(newest.id.uuidString)-\(newest.date.timeIntervalSince1970)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: .center) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NotificationCenter.default.post(name: .highlightNewItem, object: newest.id)
                    }
                }
            }
        }
        .onChange(of: showingAddIncome) { old, new in
            if !old && new {
                incomeCountBeforeAdd = incomes.count
            } else if old && !new {
                if incomes.count > incomeCountBeforeAdd,
                   let newest = incomes.max(by: { $0.createdAt < $1.createdAt }) {
                    let targetID = "\(newest.id.uuidString)-\(newest.date.timeIntervalSince1970)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: .center) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NotificationCenter.default.post(name: .highlightNewItem, object: newest.id)
                    }
                }
            }
        }
        .onChange(of: showingReallocateFunds) { old, new in
            if !old && new {
                reallocationCountBeforeAdd = reallocations.count
            } else if old && !new {
                if reallocations.count > reallocationCountBeforeAdd,
                   let newest = reallocations.activeIn(yearMonth: currentYearMonth)
                       .max(by: { $0.createdAt < $1.createdAt }) {
                    let targetID = newest.id.uuidString
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: .center) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NotificationCenter.default.post(name: .highlightNewItem, object: newest.id)
                    }
                }
            }
        }
        .onChange(of: attachments) { old, new in
            guard !isInitialLoad else { return }
            let oldMonth = old.filter { $0.month == currentYearMonth.month && $0.year == currentYearMonth.year }
            let newMonth = new.filter { $0.month == currentYearMonth.month && $0.year == currentYearMonth.year }
            guard newMonth.count > oldMonth.count,
                  let newest = newMonth.max(by: { $0.dateAdded < $1.dateAdded }) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(newest.id, anchor: .center) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: .highlightNewItem, object: newest.id)
            }
        }
        .onCategoryRenamed(expenses: $expenses, incomes: $incomes)
        .background {
            AlertContainer {
                Color.clear
                    // First alert: Choose deletion scope for recurring items
                    .alert("Delete Recurring Item", isPresented: $showingRecurringScopeAlert) {
                        Button("All Occurrences", role: .destructive) {
                            pendingRecurringScope = .all
                            // Delay showing next alert to allow this one to dismiss
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showingDeleteConfirmation = true
                            }
                        }
                        Button("Current And Future", role: .destructive) {
                            pendingRecurringScope = .currentAndFuture
                            // Delay showing next alert to allow this one to dismiss
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showingDeleteConfirmation = true
                            }
                        }
                        Button("Current Occurrence", role: .destructive) {
                            pendingRecurringScope = .currentOnly
                            // Delay showing next alert to allow this one to dismiss
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showingDeleteConfirmation = true
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            expenseToDelete = nil
                            incomeToDelete = nil
                        }
                    } message: {
                        Text("This is a recurring item. Choose which occurrences to delete:")
                    }
                    // Duplication scope alert for recurring items
                    .alert("Duplicate Recurring Item", isPresented: $showingRecurringDuplicateScopeAlert) {
                        Button("All Occurrences") { performDuplicate(scope: .all) }
                        Button("Current And Future") { performDuplicate(scope: .currentAndFuture) }
                        Button("Current Occurrence") { performDuplicate(scope: .currentOnly) }
                        Button("Cancel", role: .cancel) { clearDuplicateState() }
                    } message: {
                        Text("This is a recurring item. Choose which occurrences to duplicate:")
                    }
                    // Second alert: Confirm deletion
                    .alert(getDeleteAlertTitle(), isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { 
                            expenseToDelete = nil
                            incomeToDelete = nil
                            pendingRecurringScope = nil
                            reallocationToDelete = nil
                        }
                        Button("Delete", role: .destructive) {
                            handleDeleteConfirmation()
                        }
                    } message: {
                        Text(getDeleteAlertMessage())
                    }
            }
        }
        .sheet(item: $localExpenseToEdit) { expense in
            if let expenseBinding = SafeBindingHelper.binding(for: expense, in: $expenses) {
                EditExpenseView(expense: expenseBinding, expenses: $expenses, occurrenceDate: expense.date, item: item)
                    .standardSheetPresentation()
            } else {
                Text("Expense not found")
                    .onAppear {
                        localExpenseToEdit = nil
                    }
            }
        }
        .sheet(item: $localIncomeToEdit) { income in
            if let incomeBinding = SafeBindingHelper.binding(for: income, in: $incomes) {
                EditIncomeView(income: incomeBinding, incomes: $incomes, item: item, occurrenceDate: income.date)
                    .standardSheetPresentation()
            } else {
                Text("Income not found")
                    .onAppear {
                        localIncomeToEdit = nil
                    }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(expenses: $expenses, selectedMonth: currentYearMonth.month, selectedYear: currentYearMonth.year, selectedDay: defaultDayForMonth, defaultDate: defaultDateForMonth, item: item)
                .standardSheetPresentation()
        }
        .sheet(isPresented: $showingAddIncome) {
            AddIncomeView(incomes: $incomes, item: item, showRecurringOption: true, defaultShowDate: true, showMonthSelector: false, selectedMonth: currentYearMonth.month, selectedYear: currentYearMonth.year, selectedDay: defaultDayForMonth, defaultDate: defaultDateForMonth)
                .standardSheetPresentation()
        }
        .sheet(isPresented: $showingReallocateFunds) {
            ReallocateFundsView(reallocations: $reallocations, expenses: $expenses, incomes: $incomes, item: item, selectedMonth: nil, selectedYear: nil)
                .standardSheetPresentation()
        }
        .sheet(item: $reallocationToEdit) { reallocation in
            if let reallocationBinding = SafeBindingHelper.binding(for: reallocation, in: $reallocations) {
                EditReallocateFundsView(reallocation: reallocationBinding, reallocations: $reallocations, expenses: $expenses, incomes: $incomes, item: item)
                    .standardSheetPresentation()
            } else {
                Text("Reallocation not found")
                    .onAppear {
                        reallocationToEdit = nil
                    }
            }
        }
        .sheet(item: $attachmentToView) { (attachment: BudgetAttachment) in
            BudgetAttachmentViewerSheet(attachments: $attachments, attachment: attachment)
        }
        .budgetAttachmentPickers(
            showingPhotoPicker: $showingBudgetPhotoPicker,
            showingFilePicker: $showingBudgetFilePicker,
            attachments: $attachments,
            month: currentYearMonth.month,
            year: currentYearMonth.year
        )
        .sheet(isPresented: $showingIncomeView) {
            BudgetIncomeSheetView(item: item, incomes: $incomes, attachments: $attachments) { selected in
                showingIncomeView = false
                monthOffset = (selected.year - yearMonth.year) * 12 + (selected.month - yearMonth.month)
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterOptionsSheet(
                transactionFilter: $transactionFilter,
                selectedCategories: $selectedCategories,
                item: item,
                highlightColor: highlightColor,
                month: currentYearMonth.month,
                year: currentYearMonth.year
            )
        }
        } // end ScrollViewReader
    }

    // MARK: - Custom Calendar View
    
    @ViewBuilder
    private func makeCustomCalendarView() -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        
        VStack(spacing: 6) {
            // Weekday headers using same grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid - flatten weeks into a single grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(flattenedCalendarDays, id: \.offset) { item in
                    if let day = item.day {
                        customCalendarDayButton(for: day)
                    } else {
                        // Empty space for days before/after month
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .overlay(
                CalendarDragOverlay(
                    calendarDays: flattenedCalendarDays.map { $0.day },
                    onToggleDay: { day in
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    },
                    onClearSelection: {
                        selectedDays.removeAll()
                    }
                )
            )
        }
        .padding(.horizontal, -8)
        .padding(.vertical, 1)
    }
    
    @ViewBuilder
    private func customCalendarDayButton(for day: Int) -> some View {
        let hasIncome = dayHasIncome(day)
        let hasExpenses = dayHasExpenses(day)
        let hasReallocations = dayHasReallocations(day)
        let isSelected = selectedDays.contains(day)
        let isToday = isTodayInCurrentMonth(day: day)
        
        VStack(spacing: 4) {
            ZStack {
                // Selection circle behind the text
                Circle()
                    .fill(isSelected ? highlightColor : Color.clear)
                    .frame(width: 30, height: 30)
                
                Text("\(day)")
                    .font(.body)
                    .fontWeight((isSelected || isToday) ? .bold : .medium)
                    .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : (isToday ? highlightColor : .primary))
            }
            
            // Pill indicator - shows income, expenses, and reallocations
            pillIndicator(hasIncome: hasIncome, hasExpenses: hasExpenses, hasReallocations: hasReallocations, day: day)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func pillIndicator(hasIncome: Bool, hasExpenses: Bool, hasReallocations: Bool, day: Int) -> some View {
        // Determine net reallocation direction for this day if reallocations exist
        let netReallocationIsPositive: Bool? = {
            guard hasReallocations else { return nil }
            let dayReallocations = reallocationsForDay(day)
            let netAmount = dayReallocations.map { $0.signedAmount }.sumMoney()
            return !netAmount.isEffectivelyNegative
        }()
        
        // Determine which categories have activity
        let hasIncomeActivity = hasIncome || (netReallocationIsPositive == true)
        let hasExpenseActivity = hasExpenses || (netReallocationIsPositive == false)
        
        if hasIncomeActivity && hasExpenseActivity {
            // Both income/positive reallocations and expenses/negative reallocations - split pill
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .green, location: 0.0),
                            .init(color: .green, location: 0.5),
                            .init(color: .red, location: 0.5),
                            .init(color: .red, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 30, height: 4)
        } else if hasIncomeActivity {
            // Only income or positive reallocations - green pill
            Capsule()
                .fill(.green)
                .frame(width: 30, height: 4)
        } else if hasExpenseActivity {
            // Only expenses or negative reallocations - red pill
            Capsule()
                .fill(.red)
                .frame(width: 30, height: 4)
        } else {
            // No activity - filled pill to show available days
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 30, height: 4)
        }
    }
    
    // MARK: - Calendar Helper Properties
    
    // Get number of days in selected month
    private var daysInMonth: Int {
        let calendar = Calendar.current
        let dateComponents = DateComponents(year: currentYearMonth.year, month: currentYearMonth.month)
        guard let date = calendar.date(from: dateComponents),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }
    
    // Get the weekday of the first day of the month (1 = Sunday, 7 = Saturday)
    private var firstWeekday: Int {
        let calendar = Calendar.current
        let dateComponents = DateComponents(year: currentYearMonth.year, month: currentYearMonth.month, day: 1)
        guard let date = calendar.date(from: dateComponents) else {
            return 1
        }
        return calendar.component(.weekday, from: date)
    }
    
    // Generate weeks for the calendar
    private var calendarWeeks: [[Int?]] {
        var weeks: [[Int?]] = []
        var currentWeek: [Int?] = []
        
        // Add empty cells before first day
        for _ in 1..<firstWeekday {
            currentWeek.append(nil)
        }
        
        // Add all days
        for day in 1...daysInMonth {
            currentWeek.append(day)
            
            // If we've completed a week (7 days), start a new week
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }
        
        // Add the last partial week if it exists
        if !currentWeek.isEmpty {
            // Fill remaining days with nil
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }
        
        return weeks
    }
    
    // Flatten calendar weeks into a single array for LazyVGrid
    private var flattenedCalendarDays: [(offset: Int, day: Int?)] {
        calendarWeeks.flatMap { $0 }.enumerated().map { (offset: $0.offset, day: $0.element) }
    }
    
    // Check if a day has income
    private func dayHasIncome(_ day: Int) -> Bool {
        !incomesForDay(day).isEmpty
    }
    
    // Check if a day has expenses
    private func dayHasExpenses(_ day: Int) -> Bool {
        !expensesForDay(day).isEmpty
    }
    
    // Check if a day has reallocations
    private func dayHasReallocations(_ day: Int) -> Bool {
        !reallocationsForDay(day).isEmpty
    }
    
    // Check if a day has any activity
    private func dayHasActivity(_ day: Int) -> Bool {
        !incomesForDay(day).isEmpty || !expensesForDay(day).isEmpty || !reallocationsForDay(day).isEmpty
    }
    
    // Get incomes for a specific day
    private func incomesForDay(_ day: Int) -> [Income] {
        var incomesForThisDay: [Income] = []
        for income in monthIncomes {
            if income.isRecurring {
                if shouldRecurringItemAppearOnDay(
                    startDate: income.date, endDate: income.endDate,
                    frequency: income.recurringFrequency.rawValue, day: day,
                    month: currentYearMonth.month, year: currentYearMonth.year,
                    rule: income.resolvedRule
                ),
                   let occurrence = income.withOccurrenceDate(day: day, month: currentYearMonth.month, year: currentYearMonth.year) {
                    incomesForThisDay.append(occurrence)
                }
            } else if income.date.year == currentYearMonth.year && income.date.month == currentYearMonth.month && income.date.day == day {
                incomesForThisDay.append(income)
            }
        }
        return incomesForThisDay
    }
    
    // Expand recurring incomes into individual occurrences for the entire month
    private func expandedMonthIncomes() -> [Income] {
        let calendar = Calendar.current
        var expandedIncomes: [Income] = []
        
        // Get the number of days in the viewing month
        guard let monthRange = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: currentYearMonth.year, month: currentYearMonth.month, day: 1)) ?? Date()) else {
            return monthIncomes
        }
        
        for income in monthIncomes {
            if income.isRecurring {
                // For recurring items, create an instance for each day it appears
                for day in monthRange {
                    if shouldRecurringItemAppearOnDay(
                        startDate: income.date, endDate: income.endDate,
                        frequency: income.recurringFrequency.rawValue,
                        day: day, month: currentYearMonth.month, year: currentYearMonth.year,
                        rule: income.resolvedRule
                    ),
                       let occurrence = income.withOccurrenceDate(day: day, month: currentYearMonth.month, year: currentYearMonth.year) {
                        expandedIncomes.append(occurrence)
                    }
                }
            } else {
                // For non-recurring items, just add them as-is
                expandedIncomes.append(income)
            }
        }
        
        return expandedIncomes
    }
    
    // Get expenses for a specific day
    private func expensesForDay(_ day: Int) -> [Expense] {
        var expensesForThisDay: [Expense] = []
        for expense in monthExpenses {
            if expense.isRecurring || expense.isMonthlyPaymentPlan {
                if shouldRecurringItemAppearOnDay(
                    startDate: expense.date, endDate: expense.endDate,
                    frequency: expense.effectiveFrequency, day: day,
                    month: currentYearMonth.month, year: currentYearMonth.year,
                    rule: expense.resolvedRule
                ),
                   let occurrence = expense.withOccurrenceDate(day: day, month: currentYearMonth.month, year: currentYearMonth.year) {
                    expensesForThisDay.append(occurrence)
                }
            } else if expense.date.year == currentYearMonth.year && expense.date.month == currentYearMonth.month && expense.date.day == day {
                expensesForThisDay.append(expense)
            }
        }
        return expensesForThisDay
    }
    
    // Expand recurring expenses into individual occurrences for the entire month
    private func expandedMonthExpenses() -> [Expense] {
        let calendar = Calendar.current
        var expandedExpenses: [Expense] = []
        
        // Get the number of days in the viewing month
        guard let monthRange = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: currentYearMonth.year, month: currentYearMonth.month, day: 1)) ?? Date()) else {
            return monthExpenses
        }
        
        for expense in monthExpenses {
            let isRecurring = expense.isRecurring || expense.isMonthlyPaymentPlan
            if isRecurring {
                // For recurring items, create an instance for each day it appears
                let frequency = expense.effectiveFrequency
                for day in monthRange {
                    if shouldRecurringItemAppearOnDay(
                        startDate: expense.date, endDate: expense.endDate,
                        frequency: frequency, day: day,
                        month: currentYearMonth.month, year: currentYearMonth.year,
                        rule: expense.resolvedRule
                    ),
                       let occurrence = expense.withOccurrenceDate(day: day, month: currentYearMonth.month, year: currentYearMonth.year) {
                        expandedExpenses.append(occurrence)
                    }
                }
            } else {
                // For non-recurring items, just add them as-is
                expandedExpenses.append(expense)
            }
        }
        
        return expandedExpenses
    }
    
    // Get reallocations for a specific day
    private func reallocationsForDay(_ day: Int) -> [Reallocation] {
        let calendar = Calendar.current
        
        // Filter reallocations that belong to this month
        let monthReallocations = reallocations.activeIn(yearMonth: currentYearMonth)
        
        // Filter by specific day
        return monthReallocations.filter { reallocation in
            let reallocationDay = calendar.component(.day, from: reallocation.date)
            return reallocationDay == day
        }
    }
    
    // Helper to check if a day is today in the current viewing month
    private func isTodayInCurrentMonth(day: Int) -> Bool {
        let now = Date()
        return currentYearMonth.year == now.year && currentYearMonth.month == now.month && day == now.day
    }
    
    // MARK: - Helper Methods
    
    /// Create a reallocation row view
    private func reallocationRow(for reallocation: Reallocation) -> some View {
        let linkedDate = reallocations.first(where: { $0.id == reallocation.linkedId })?.date ?? reallocation.date
        return HighlightableReallocationRow(
            reallocation: reallocation,
            linkedDate: linkedDate,
            isSelecting: isSelecting,
            isSelected: selectedReallocations.contains(reallocation.id),
            highlightColor: highlightColor,
            dateFormat: dateFormat,
            selectedCurrency: selectedCurrency,
            onTap: {
                if isSelecting {
                    toggleReallocationSelectionState(for: reallocation)
                } else {
                    reallocationToEdit = reallocation
                }
            },
            onDelete: {
                reallocationToDelete = reallocation
                showingDeleteConfirmation = true
            }
        )
    }
    
    private func scopeDeletionSuffix(for scope: RecurringScope?) -> String {
        guard let scope else { return "" }
        switch scope {
        case .currentOnly: return " from this month only"
        case .currentAndFuture: return " from this month and all future occurrences"
        case .all: return " (all occurrences)"
        }
    }

    /// Returns the appropriate alert title based on which item is being deleted
    private func getDeleteAlertTitle() -> String {
        if expenseToDelete != nil {
            return "Delete Expense?"
        } else if incomeToDelete != nil {
            return "Delete Income?"
        } else if reallocationToDelete != nil {
            return "Delete Reallocation?"
        } else {
            return "Delete Selected Items?"
        }
    }
    
    /// Handles the deletion based on type and scope
    /// For reallocations, deletes both paired entries
    /// For bulk deletes, processes all selected items (current occurrence only for recurring items)
    private func handleDeleteConfirmation() {
        if let expense = expenseToDelete {
            removeExpense(expense)
            expenseToDelete = nil
        } else if let income = incomeToDelete {
            removeIncome(income)
            incomeToDelete = nil
        } else if let reallocation = reallocationToDelete {
            // Delete both paired reallocations
            reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
            reallocationToDelete = nil
        } else {
            // Bulk delete - delete all occurrences in the viewed month for recurring items (no scope prompts)
            
            // Process each expense — occurrence key holds the exact date the user selected
            for occKey in selectedExpenses {
                if let expense = expenses.first(where: { $0.id == occKey.id }) {
                    if expense.isRecurring || expense.isMonthlyPaymentPlan {
                        deleteCurrentOccurrenceOfExpense(expense, occurrenceDate: occKey.date)
                    } else {
                        expenses.removeAll { $0.id == expense.id }
                    }
                }
            }

            // Process each income — occurrence key holds the exact date the user selected
            for occKey in selectedIncomes {
                if let income = incomes.first(where: { $0.id == occKey.id }) {
                    if income.isRecurring {
                        deleteCurrentOccurrenceOfIncome(income, occurrenceDate: occKey.date)
                    } else {
                        incomes.removeAll { $0.id == income.id }
                    }
                }
            }
            
            // Process each reallocation (delete both paired entries)
            for reallocationID in selectedReallocations {
                if let reallocation = reallocations.first(where: { $0.id == reallocationID }) {
                    // Delete both the selected reallocation and its linked pair
                    reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
                }
            }
            
            // Process each attachment
            for attachmentID in selectedAttachments {
                attachments.removeAll { $0.id == attachmentID }
            }
            
            exitSelectionMode()
        }
        pendingRecurringScope = nil
    }
    
    private func deleteCurrentOccurrenceOfExpense(_ expense: Expense, occurrenceDate: Date) {
        guard let adjusted = expense.withOccurrenceDate(day: occurrenceDate.day, month: occurrenceDate.month, year: occurrenceDate.year) else { return }
        pendingRecurringScope = .currentOnly
        removeExpense(adjusted)
    }
    
    private func deleteCurrentOccurrenceOfIncome(_ income: Income, occurrenceDate: Date) {
        guard let adjusted = income.withOccurrenceDate(day: occurrenceDate.day, month: occurrenceDate.month, year: occurrenceDate.year) else { return }
        pendingRecurringScope = .currentOnly
        removeIncome(adjusted)
    }

    // Removes all occurrences of a recurring expense within the viewed month.
    // Handles weekly/bi-weekly expenses that appear multiple times per month — a single
    // deleteCurrentOccurrenceOfExpense call would leave remaining occurrences because the
    // resulting "after" segment (new UUID) still starts inside the same month.
    private func deleteAllMonthOccurrencesOfExpense(_ expense: Expense) {
        let month = currentYearMonth.month
        let year = currentYearMonth.year
        let calendar = Calendar.current
        guard let monthFirstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthFirstDay) else { return }

        guard let firstOccurrenceDate = findOccurrenceDateForExpense(expense, inMonth: month, year: year, onDay: nil) else {
            expenses.removeAll { $0.id == expense.id }
            return
        }

        var lastOccurrenceDay = calendar.component(.day, from: firstOccurrenceDate)
        for day in monthRange {
            if shouldRecurringItemAppearOnDay(startDate: expense.date, endDate: expense.endDate,
                                              frequency: expense.effectiveFrequency,
                                              day: day, month: month, year: year,
                                              rule: expense.resolvedRule) {
                lastOccurrenceDay = day
            }
        }
        var lastComps = DateComponents()
        lastComps.year = year; lastComps.month = month; lastComps.day = lastOccurrenceDay
        lastComps.hour = calendar.component(.hour, from: expense.date)
        lastComps.minute = calendar.component(.minute, from: expense.date)
        let lastOccurrenceDate = calendar.date(from: lastComps) ?? firstOccurrenceDate

        let normalizedLastOcc = calendar.startOfDay(for: lastOccurrenceDate)
        let nextOcc = findNextOccurrence(after: normalizedLastOcc, startDate: expense.date, frequency: expense.effectiveFrequency, rule: expense.resolvedRule)

        guard let index = expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        let original = expenses[index]
        let normalizedFirstOcc = calendar.startOfDay(for: firstOccurrenceDate)
        let normalizedStart = calendar.startOfDay(for: original.date)

        if normalizedFirstOcc == normalizedStart {
            if let end = original.endDate, nextOcc > end {
                expenses.removeAll { $0.id == expense.id }
            } else {
                var updated = original
                updated.date = nextOcc
                expenses[index] = updated
            }
        } else {
            guard let dayBeforeFirstOcc = calendar.date(byAdding: .day, value: -1, to: normalizedFirstOcc) else {
                expenses.removeAll { $0.id == expense.id }
                return
            }
            var before = original
            before.endDate = dayBeforeFirstOcc
            before.showEndDate = true
            expenses[index] = before
            let shouldCreateAfter = original.endDate.map { nextOcc <= $0 } ?? true
            if shouldCreateAfter {
                var after = original.duplicate()
                after.date = nextOcc
                expenses.append(after)
            }
        }
    }

    // Removes all occurrences of a recurring income within the viewed month.
    private func deleteAllMonthOccurrencesOfIncome(_ income: Income) {
        let month = currentYearMonth.month
        let year = currentYearMonth.year
        let calendar = Calendar.current
        guard let monthFirstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthFirstDay) else { return }

        guard let firstOccurrenceDate = findOccurrenceDateForIncome(income, inMonth: month, year: year, onDay: nil) else {
            incomes.removeAll { $0.id == income.id }
            return
        }

        var lastOccurrenceDay = calendar.component(.day, from: firstOccurrenceDate)
        for day in monthRange {
            if shouldRecurringItemAppearOnDay(startDate: income.date, endDate: income.endDate,
                                              frequency: income.recurringFrequency.rawValue,
                                              day: day, month: month, year: year,
                                              rule: income.resolvedRule) {
                lastOccurrenceDay = day
            }
        }
        var lastComps = DateComponents()
        lastComps.year = year; lastComps.month = month; lastComps.day = lastOccurrenceDay
        lastComps.hour = calendar.component(.hour, from: income.date)
        lastComps.minute = calendar.component(.minute, from: income.date)
        let lastOccurrenceDate = calendar.date(from: lastComps) ?? firstOccurrenceDate

        let normalizedLastOcc = calendar.startOfDay(for: lastOccurrenceDate)
        let nextOcc = findNextOccurrence(after: normalizedLastOcc, startDate: income.date, frequency: income.recurringFrequency.rawValue, rule: income.resolvedRule)

        guard let index = incomes.firstIndex(where: { $0.id == income.id }) else { return }
        let original = incomes[index]
        let normalizedFirstOcc = calendar.startOfDay(for: firstOccurrenceDate)
        let normalizedStart = calendar.startOfDay(for: original.date)

        if normalizedFirstOcc == normalizedStart {
            if let end = original.endDate, nextOcc > end {
                incomes.removeAll { $0.id == income.id }
            } else {
                var updated = original
                updated.date = nextOcc
                incomes[index] = updated
            }
        } else {
            guard let dayBeforeFirstOcc = calendar.date(byAdding: .day, value: -1, to: normalizedFirstOcc) else {
                incomes.removeAll { $0.id == income.id }
                return
            }
            var before = original
            before.endDate = dayBeforeFirstOcc
            before.showEndDate = true
            incomes[index] = before
            let shouldCreateAfter = original.endDate.map { nextOcc <= $0 } ?? true
            if shouldCreateAfter {
                var after = original.duplicate()
                after.date = nextOcc
                incomes.append(after)
            }
        }
    }

    /// Finds the occurrence date for a recurring expense in the viewed month/day
    /// Returns the date of the specific occurrence that's being displayed
    /// - Parameters:
    ///   - expense: The recurring expense
    ///   - month: The month being viewed (1-12)
    ///   - year: The year being viewed
    ///   - day: Optional specific day being viewed (nil means whole month)
    /// - Returns: The occurrence date, or nil if not found
    private func findOccurrenceDateForExpense(_ expense: Expense, inMonth month: Int, year: Int, onDay day: Int?) -> Date? {
        findOccurrenceDateForRecurringItem(startDate: expense.date, endDate: expense.endDate, frequency: expense.effectiveFrequency, inMonth: month, year: year, onDay: day, rule: expense.resolvedRule)
    }

    private func findOccurrenceDateForIncome(_ income: Income, inMonth month: Int, year: Int, onDay day: Int?) -> Date? {
        findOccurrenceDateForRecurringItem(startDate: income.date, endDate: income.endDate, frequency: income.recurringFrequency.rawValue, inMonth: month, year: year, onDay: day, rule: income.resolvedRule)
    }

    
    private func getDeleteAlertMessage() -> String {
        if let expense = expenseToDelete {
            return "This will permanently delete '\(expense.name)'\(scopeDeletionSuffix(for: pendingRecurringScope)). This action cannot be undone."
        } else if let income = incomeToDelete {
            return "This will permanently delete '\(income.name)'\(scopeDeletionSuffix(for: pendingRecurringScope)). This action cannot be undone."
        } else if let reallocation = reallocationToDelete {
            // Generate automatic title for the deletion message
            let monthName = monthDisplayName(reallocation.isFromEntry ? reallocation.toMonth : reallocation.fromMonth)
            let year = reallocation.isFromEntry ? reallocation.toYear : reallocation.fromYear
            let autoTitle = reallocation.isFromEntry ? "To \(monthName) \(year)" : "From \(monthName) \(year)"
            return "This will permanently delete the reallocation '\(autoTitle)'. This action cannot be undone."
        } else {
            // Bulk delete message
            let totalSelected = selectedExpenses.count + selectedIncomes.count + selectedReallocations.count + selectedAttachments.count
            var message = "This will permanently delete \(totalSelected) item\(totalSelected == 1 ? "" : "s")"
            
            // For bulk deletes, we always delete current occurrence only (no scope selection)
            // Check if any selected items are recurring
            let hasRecurringItems = selectedExpenses.contains(where: { key in
                expenses.first(where: { $0.id == key.id })?.isRecurring == true ||
                expenses.first(where: { $0.id == key.id })?.isMonthlyPaymentPlan == true
            }) || selectedIncomes.contains(where: { key in
                incomes.first(where: { $0.id == key.id })?.isRecurring == true
            })
            
            if hasRecurringItems {
                message += " (current occurrences only for recurring items)"
            }
            
            message += ". This action cannot be undone."
            return message
        }
    }
    
    /// Calculate the display date for an expense in the current viewing month
    private func calculateDisplayDate(for expense: Expense) -> Date {
        let calendar = Calendar.current
        let originalDay = calendar.component(.day, from: expense.date)
        let originalHour = calendar.component(.hour, from: expense.date)
        let originalMinute = calendar.component(.minute, from: expense.date)
        
        // Check if original date is last day of its month
        let isOriginalLastDay = expense.date.isLastDayOfMonth
        
        var components = DateComponents()
        components.year = currentYearMonth.year
        components.month = currentYearMonth.month
        components.hour = originalHour
        components.minute = originalMinute
        
        if isOriginalLastDay {
            // If original was last day of month, use last day of current month
            if let firstOfMonth = calendar.date(from: components),
               let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
                components.day = range.count
            } else {
                components.day = originalDay
            }
        } else {
            // For regular days, use the original day or closest valid day
            if let firstOfMonth = calendar.date(from: DateComponents(year: currentYearMonth.year, month: currentYearMonth.month)),
               let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
                components.day = min(originalDay, range.count)
            } else {
                components.day = originalDay
            }
        }
        
        return calendar.date(from: components) ?? expense.date
    }
    
    // MARK: - Data Persistence

    private func loadBudgetData() {
        guard let data = item.decodeBudgetData() else { isInitialLoad = false; return }
        expenses = data.expenses; incomes = data.incomes
        attachments = data.attachments; reallocations = data.reallocations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInitialLoad = false
            print("✅ Initial load complete - persistence enabled")
        }
    }

    private func persistBudgetData() {
        saveBudgetData(to: item, expenses: expenses, incomes: incomes,
                       attachments: attachments, reallocations: reallocations)
    }

    /// Builds the content for an expense row with date, frequency, and amount information
    /// Extracted as a separate function to avoid compiler timeout issues
    private func makeExpenseRowContent(for expense: Expense) -> some View {
        HighlightableExpenseRow(
            expense: expense,
            displayDate: calculateDisplayDate(for: expense),
            dateFormat: dateFormat,
            selectedCurrency: selectedCurrency,
            highlightColor: highlightColor
        )
    }
}

private struct HighlightableExpenseRow: View {
    let expense: Expense
    let displayDate: Date
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let highlightColor: Color

    @State private var isHighlighted = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(isHighlighted ? highlightColor : .primary)
                HStack(spacing: 4) {
                    Text(displayDate, format: dateFormat.style)
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? highlightColor : .secondary)

                    if expense.isMonthlyPaymentPlan || expense.isRecurring {
                        Text("• \(expense.effectiveFrequency)")
                            .font(.caption)
                            .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if expense.isMonthlyPaymentPlan, let total = expense.totalAmount {
                    Text(expense.amount, format: .currency(code: selectedCurrency.code))
                        .foregroundStyle(isHighlighted ? highlightColor : .red)
                    HStack(spacing: 4) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                        Text(total, format: .currency(code: selectedCurrency.code))
                            .font(.caption)
                            .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                    }
                } else {
                    Text(expense.amount, format: .currency(code: selectedCurrency.code))
                        .foregroundStyle(isHighlighted ? highlightColor : .red)
                }
            }
        }
        .animation(.default, value: isHighlighted)
        .onReceive(NotificationCenter.default.publisher(for: .highlightNewItem)) { notification in
            guard let id = notification.object as? UUID, id == expense.id else { return }
            isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isHighlighted = false
            }
        }
    }
}

private struct HighlightableReallocationRow: View {
    let reallocation: Reallocation
    let linkedDate: Date
    let isSelecting: Bool
    let isSelected: Bool
    let highlightColor: Color
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHighlighted = false

    var body: some View {
        let toFromPrefix = reallocation.isFromEntry ? "To" : "From"
        let amount = reallocation.signedAmount
        let absAmount = abs(amount)

        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
                    .padding(.trailing, 12)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reallocation")
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(isHighlighted ? highlightColor : .primary)
                    HStack(spacing: 4) {
                        Text(reallocation.date, format: dateFormat.style)
                            .font(.caption)
                            .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                        Text("• \(toFromPrefix) \(linkedDate.formatted(dateFormat.style))")
                            .font(.caption)
                            .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                    }
                }
                Spacer()
                Text(absAmount.formatted(.currency(code: selectedCurrency.code)))
                    .foregroundStyle(isHighlighted ? highlightColor : (amount.isEffectivelyZero || amount.isEffectivelyPositive ? .green : .red))
            }
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .if(!isSelecting) { view in
            view
                .contextMenu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .tint(nil)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
        }
        .animation(.default, value: isHighlighted)
        .onReceive(NotificationCenter.default.publisher(for: .highlightNewItem)) { notification in
            guard let id = notification.object as? UUID, id == reallocation.id else { return }
            isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isHighlighted = false
            }
        }
    }
}
