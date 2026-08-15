//
//  BudgetVisualizerPageView.swift
//  Bookee
//
//  Detail view showing the full budget for a single item, with monthly breakdown,
//  expense/income tracking, tax calculations, and attachments.
//

import SwiftUI
import UIKit
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Auto Reallocation Summary

private struct AutoReallocationSummary {
    let totalAmount: Double
    let sources: [(month: Int, year: Int, amount: Double)]
    let toMonth: Int
    let toYear: Int
}

// MARK: - Budget Visualizer Page View

/// Detail view for displaying and managing budget/income tracking for a specific item
/// Shows monthly overview, all expenses and incomes, tax calculations, and attachments
/// Supports year selection, item editing, and comprehensive budget visualization
struct BudgetVisualizerPageView: View {
    @Bindable var item: Item
    var navigationPath: Binding<NavigationPath>? = nil
    @State private var expenses: [Expense] = []
    @State private var incomes: [Income] = []
    @State private var attachments: [BudgetAttachment] = []
    @State private var reallocations: [Reallocation] = []
    @State private var attachmentToView: BudgetAttachment?
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingReallocateFunds = false
    @State private var isInitialLoad = true // Prevents automatic year updates after initial load
    
    // File and photo picker states
    @State private var showingBudgetPhotoPicker = false
    @State private var showingBudgetFilePicker = false

    @State private var expenseToEdit: Expense?
    @State private var incomeToEdit: Income?
    @State private var showingEditDetails = false
    @State private var rowVisibilitySnapshot: (showTaxes: Bool, isTaxEnabled: Bool, showReallocations: Bool, showSurplus: Bool)? = nil
    @State private var isSelecting = false
    @State private var selectedExpenses = Set<UUID>()
    @State private var selectedIncomes = Set<UUID>()
    @State private var selectedReallocations = Set<UUID>()
    @State private var selectedAttachments = Set<UUID>()
    @State private var selectedYear: Int = Date().year

    @State private var showingIncomeView = false
    @State private var scrollToCurrentMonthCounter = 0 // Incremented to trigger scroll to current month
    @State private var pendingScrollYearMonth: YearMonth? // Deferred scroll target when year must change first
    @State private var pendingScrollAnimated = true // Whether the deferred scroll should animate
    @State private var didInitialAppear = false // Prevents body onAppear from overriding selectedYear on reappear
    @State private var showingDeleteConfirmation = false // Confirmation alert for deletions
    @State private var autoReallocationAlert: AutoReallocationSummary?
    @State private var expenseCountBeforeAdd = 0
    @State private var incomeCountBeforeAdd = 0
    @State private var reallocationCountBeforeAdd = 0
    @State private var highlightedHeaderYearMonth: YearMonth?
    @State private var pendingHighlightRowID: String?
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true
    
    // MARK: - Budget Calculations

    var incomesByYearMonth: [YearMonth: [Income]] { groupByYearMonth(incomes, selectedYear: selectedYear) }
    var expensesByYearMonth: [YearMonth: [Expense]] { groupByYearMonth(expenses, selectedYear: selectedYear) }
    var visibleYearMonths: [YearMonth] { allYearMonths(for: selectedYear) }
    
    /// Returns the effective amount for a recurring item in a given month,
    /// multiplying by occurrence count for recurring items.
    private func effectiveAmount<T: RecurringItem>(for item: T, in yearMonth: YearMonth) -> Double {
        guard item.isEffectivelyRecurring else { return item.amount }
        let occurrences = countOccurrencesInMonth(
            startDate: item.date,
            endDate: item.endDate,
            frequency: item.effectiveFrequency,
            month: yearMonth.month,
            year: yearMonth.year,
            rule: item.resolvedRule
        )
        return roundMoney(item.amount * Double(occurrences))
    }

    func totalIncomeForYearMonth(_ yearMonth: YearMonth) -> Double {
        (incomesByYearMonth[yearMonth] ?? []).map { effectiveAmount(for: $0, in: yearMonth) }.sumMoney()
    }

    func taxableIncomeForYearMonth(_ yearMonth: YearMonth) -> Double {
        guard item.isTaxSavingsEnabled else { return 0.0 }
        return (incomesByYearMonth[yearMonth] ?? []).filter { $0.isTaxable }.map { effectiveAmount(for: $0, in: yearMonth) }.sumMoney()
    }

    func untaxableIncomeForYearMonth(_ yearMonth: YearMonth) -> Double {
        (incomesByYearMonth[yearMonth] ?? []).filter { item.isTaxSavingsEnabled ? !$0.isTaxable : true }.map { effectiveAmount(for: $0, in: yearMonth) }.sumMoney()
    }
    
    func totalExpensesForYearMonth(_ yearMonth: YearMonth) -> Double {
        (expensesByYearMonth[yearMonth] ?? []).map { effectiveAmount(for: $0, in: yearMonth) }.sumMoney()
    }
    
    /// Calculates net reallocated funds for a specific year-month
    /// Positive values indicate funds added to the month, negative values indicate funds removed
    /// Accounts for both "from" (subtractions) and "to" (additions) entries
    func reallocatedFundsForYearMonth(_ yearMonth: YearMonth) -> Double {
        let monthReallocations = reallocations.activeIn(yearMonth: yearMonth)
        return monthReallocations.map { reallocation in
            reallocation.signedAmount
        }.sumMoney()
    }
    
    /// Calculates total positive reallocations (funds added to the month) for a specific year-month
    /// - Parameter yearMonth: The year-month to calculate for
    /// - Returns: Sum of all positive reallocations (to entries)
    func positiveReallocationsForYearMonth(_ yearMonth: YearMonth) -> Double {
        return reallocations.additionsIn(yearMonth: yearMonth).map { $0.amount }.sumMoney()
    }
    
    /// Calculates total negative reallocations (funds removed from the month) for a specific year-month
    /// - Parameter yearMonth: The year-month to calculate for
    /// - Returns: Sum of all negative reallocations (from entries) as a positive number
    func negativeReallocationsForYearMonth(_ yearMonth: YearMonth) -> Double {
        return reallocations.deductionsIn(yearMonth: yearMonth).map { $0.amount }.sumMoney()
    }
    
    // MARK: - Month Metrics

    /// Precomputed values for a month's budget display used by monthOverviewRow.
    struct MonthMetrics {
        let taxableIncome: Double
        let untaxableIncome: Double
        let expenses: Double
        let reallocated: Double
        let positiveReallocation: Double
        let negativeReallocation: Double
        let incomeNeeded: Double
        let breakEven: Double
        let remaining: Double
        /// Pre-computed tax savings for the month (0 when tax is inactive).
        /// Stored here so the "Tax Savings" display row uses the exact same value
        /// that was subtracted in the `remaining` calculation.
        let taxSavings: Double
    }

    /// Computes all budget metrics for a given year-month.
    private func computeMonthMetrics(for yearMonth: YearMonth) -> MonthMetrics {
        let monthTaxableIncome = taxableIncomeForYearMonth(yearMonth)
        let monthUntaxableIncome = untaxableIncomeForYearMonth(yearMonth)
        let monthExpenses = totalExpensesForYearMonth(yearMonth)
        let monthReallocated = reallocatedFundsForYearMonth(yearMonth)
        let positiveReallocation = positiveReallocationsForYearMonth(yearMonth)
        let negativeReallocation = negativeReallocationsForYearMonth(yearMonth)

        let totalUntaxableIncome = roundMoney(monthUntaxableIncome + positiveReallocation)
        let effectiveExpenses = roundMoney(monthExpenses + negativeReallocation)
        let expensesCoveredByUntaxable = roundMoney(min(effectiveExpenses, totalUntaxableIncome))
        let remainingExpenses = roundMoney(max(0, effectiveExpenses - expensesCoveredByUntaxable))
        // Keep divisor at full precision — rounding (1 - taxRate) to 2dp corrupts it.
        let divisor = 1.0 - item.taxRate

        let needed = divisor.isEffectivelyZero ? remainingExpenses : roundMoney(remainingExpenses / divisor)
        let s1 = roundMoney(expensesCoveredByUntaxable + needed)
        let s2 = roundMoney(s1 - monthUntaxableIncome)
        let s3 = roundMoney(s2 - positiveReallocation)
        let incomeNeeded = max(0, roundMoney(s3 - monthTaxableIncome))

        let breakEven = breakEvenDeficit(
            taxableIncome: monthTaxableIncome,
            untaxableIncome: totalUntaxableIncome,
            expenses: effectiveExpenses,
            isTaxActive: item.isTaxActive,
            taxRate: item.taxRate
        )

        // Compute tax savings once so the "Tax Savings" display row and the
        // `remaining` subtraction use the exact same rounded value.
        let monthTaxSavings = item.isTaxActive ? monthTaxableIncome.taxAmount(rate: item.taxRate) : 0.0

        var raw: Double = 0.0
        raw = roundMoney(raw + monthUntaxableIncome)
        raw = roundMoney(raw + monthTaxableIncome)
        if item.isTaxActive {
            raw = roundMoney(raw - monthTaxSavings)
        }
        raw = roundMoney(raw - monthExpenses)
        raw = roundMoney(raw + monthReallocated)
        let remaining = raw.roundedAndNormalizedMoney()

        return MonthMetrics(
            taxableIncome: monthTaxableIncome,
            untaxableIncome: monthUntaxableIncome,
            expenses: monthExpenses,
            reallocated: monthReallocated,
            positiveReallocation: positiveReallocation,
            negativeReallocation: negativeReallocation,
            incomeNeeded: incomeNeeded,
            breakEven: breakEven,
            remaining: remaining,
            taxSavings: monthTaxSavings
        )
    }

    // MARK: - View Components

    @ViewBuilder
    private func yearMonthHeaderRow(for yearMonth: YearMonth) -> some View {
        YearMonthHeaderRowView(
            yearMonth: yearMonth,
            highlightColor: highlightColor,
            isHighlighted: highlightedHeaderYearMonth == yearMonth,
            onTap: { navigationPath?.wrappedValue.append(yearMonth) }
        )
    }
    
    @ViewBuilder
    private func makeMonthListSection() -> some View {
        // Display each month in its own section - only overview rows
        ForEach(visibleYearMonths, id: \.self) { yearMonth in
            // Overview section with header - ALWAYS VISIBLE
            Section {
                monthOverviewRow(for: yearMonth)
            } header: {
                yearMonthHeaderRow(for: yearMonth)
            } footer: {
                if showFooters {
                    Text("Tap anywhere in the section to enter the details page.")
                }
            }
            .id(yearMonth) // Add ID for scrolling
        }
    }
    
    @ViewBuilder
    private func monthOverviewRow(for yearMonth: YearMonth) -> some View {
        MonthOverviewRowsView(
            m: computeMonthMetrics(for: yearMonth),
            item: item, selectedCurrency: selectedCurrency,
            yearMonth: yearMonth, navigationPath: navigationPath
        )
    }
    
    // MARK: - Main Form View
    
    private var mainFormView: some View {
        ScrollViewReader { proxy in
            Form {
                makeMonthListSection()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let target = NavigationStateManager.shared.viewedYearMonth {
                    // Do NOT clear viewedYearMonth here. body.onAppear fires after this
                    // (inner views become visible first on navigation pop), and it needs
                    // to read viewedYearMonth to override the year reset from item.targetYear.
                    scrollToYearMonth(target, proxy: proxy, animated: false)
                } else {
                    scrollToCurrentMonthIfNeeded(proxy: proxy)
                }
            }
            .onChange(of: selectedYear) { oldValue, newValue in
                if let pending = pendingScrollYearMonth {
                    pendingScrollYearMonth = nil
                    let animated = pendingScrollAnimated
                    pendingScrollAnimated = true
                    let (targetID, anchor) = scrollTargetID(for: pending.year, month: pending.month)
                    let pendingHighlight = pendingHighlightRowID
                    pendingHighlightRowID = nil
                    if animated {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: anchor) }
                        }
                        if let rowID = pendingHighlight {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                NotificationCenter.default.post(name: .highlightBudgetOverviewRow, object: rowID)
                            }
                        }
                    } else {
                        // Wait one run loop for the new year's rows to render, then position instantly.
                        DispatchQueue.main.async {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) { proxy.scrollTo(targetID, anchor: anchor) }
                        }
                    }
                } else {
                    scrollToCurrentMonthIfNeeded(proxy: proxy)
                }
            }
            .onChange(of: scrollToCurrentMonthCounter) { _, _ in
                scrollToCurrentMonth(proxy: proxy)
            }
            .onChange(of: showingAddExpense) { old, new in
                if !old && new { expenseCountBeforeAdd = expenses.count }
                else if old && !new, expenses.count > expenseCountBeforeAdd,
                        let newest = expenses.max(by: { $0.createdAt < $1.createdAt }) {
                    let ym = YearMonth(year: newest.date.year, month: newest.date.month)
                    scrollAndHighlightAfterAdd(to: ym, rowID: expenseRowID(ym), proxy: proxy)
                }
            }
            .onChange(of: showingAddIncome) { old, new in
                if !old && new { incomeCountBeforeAdd = incomes.count }
                else if old && !new, incomes.count > incomeCountBeforeAdd,
                        let newest = incomes.max(by: { $0.createdAt < $1.createdAt }) {
                    let ym = YearMonth(year: newest.date.year, month: newest.date.month)
                    scrollAndHighlightAfterAdd(to: ym, rowID: incomeRowID(taxable: newest.isTaxable, ym), proxy: proxy)
                }
            }
            .onChange(of: showingReallocateFunds) { old, new in
                if !old && new { reallocationCountBeforeAdd = reallocations.count }
                else if old && !new, reallocations.count > reallocationCountBeforeAdd,
                        let newest = reallocations.filter({ !$0.isFromEntry }).max(by: { $0.createdAt < $1.createdAt }) {
                    let ym = YearMonth(year: newest.toYear, month: newest.toMonth)
                    scrollAndHighlightAfterAdd(to: ym, rowID: reallocationRowID(ym), proxy: proxy)
                }
            }
        }
    }
    
    /// Returns the best scroll-target row ID to center the month section on screen.
    ///
    /// Anchors to the tax-savings row when it is visible — it sits at the natural
    /// boundary between income and expenses so the viewport is stable regardless of
    /// which optional rows (reallocations, other income) are toggled on or off.
    /// Falls back to the positional middle row when tax savings is not shown.
    private func scrollTargetID(for year: Int, month: Int) -> (id: String, anchor: UnitPoint) {
        // Semantic anchor: tax-savings row is always the ideal center when visible.
        if item.isTaxSavingsEnabled && item.effectiveShowTaxesGoalRow {
            return ("tax-savings-\(year)-\(month)", .center)
        }

        // Positional fallback: build the visible-row list and pick the middle entry.
        var ids: [String] = []
        if item.effectiveShowReallocationsRow { ids.append("other-income-\(year)-\(month)") }
        if item.isTaxSavingsEnabled {
            if item.effectiveShowOtherIncomeRow { ids.append("Nontaxable-income-\(year)-\(month)") }
            ids.append("taxable-income-\(year)-\(month)")
        } else {
            ids.append("Nontaxable-income-\(year)-\(month)")
        }
        // tax-savings is hidden in this branch (handled above)
        if item.effectiveShowExpensesRow        { ids.append("expenses-\(year)-\(month)") }
        if item.effectiveShowReallocationsRow   { ids.append("removed-from-\(year)-\(month)") }
        if item.effectiveShowIncomeSurplusRow   { ids.append("surplus-\(year)-\(month)") }
        return (ids[(ids.count - 1) / 2], .center)
    }
    
    private func scrollToCurrentMonthIfNeeded(proxy: ScrollViewProxy) {
        let now = Date()
        guard selectedYear == now.year else { return }
        let (targetID, anchor) = scrollTargetID(for: now.year, month: now.month)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: anchor) }
        }
    }
    
    private func scrollToCurrentMonth(proxy: ScrollViewProxy) {
        let now = Date()
        if selectedYear != now.year {
            selectedYear = now.year
            return
        }
        let (targetID, anchor) = scrollTargetID(for: now.year, month: now.month)
        withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: anchor) }
    }

    private func scrollToYearMonth(_ yearMonth: YearMonth, proxy: ScrollViewProxy, animated: Bool = true) {
        if selectedYear != yearMonth.year {
            // Store the target so onChange(of: selectedYear) can scroll there once
            // the view has re-rendered with the new year's months.
            pendingScrollYearMonth = yearMonth
            pendingScrollAnimated = animated
            selectedYear = yearMonth.year
        } else {
            let (targetID, anchor) = scrollTargetID(for: yearMonth.year, month: yearMonth.month)
            if animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo(targetID, anchor: anchor) }
                }
            } else {
                // Rows are already rendered (navigation pop) — position immediately with no animation.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo(targetID, anchor: anchor) }
            }
        }
    }
    
    // MARK: - Row ID Helpers

    private func expenseRowID(_ ym: YearMonth) -> String? {
        item.effectiveShowExpensesRow ? "expenses-\(ym.year)-\(ym.month)" : nil
    }

    private func incomeRowID(taxable: Bool, _ ym: YearMonth) -> String {
        let y = ym.year, m = ym.month
        if item.isTaxSavingsEnabled {
            if item.effectiveShowOtherIncomeRow {
                return taxable ? "taxable-income-\(y)-\(m)" : "Nontaxable-income-\(y)-\(m)"
            }
            return "taxable-income-\(y)-\(m)"
        }
        return "Nontaxable-income-\(y)-\(m)"
    }

    private func reallocationRowID(_ ym: YearMonth) -> String? {
        item.effectiveShowReallocationsRow ? "other-income-\(ym.year)-\(ym.month)" : nil
    }

    private func scrollAndHighlightAfterAdd(to ym: YearMonth, rowID: String?, proxy: ScrollViewProxy) {
        if selectedYear != ym.year {
            pendingHighlightRowID = rowID
            scrollToYearMonth(ym, proxy: proxy, animated: true)
        } else {
            scrollToYearMonth(ym, proxy: proxy, animated: true)
            if let rowID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NotificationCenter.default.post(name: .highlightBudgetOverviewRow, object: rowID)
                }
            }
        }
    }

    private var sheetsModifier: some View {
        EmptyView()
            .sheet(isPresented: $showingEditDetails) {
                NavigationStack {
                    BudgetDetailsView(
                        item: item,
                        onSave: {
                            showingEditDetails = false
                            // Backup is handled by BudgetDetailsView's saveChanges() method
                            
                            // Check if row visibility settings changed and trigger scroll if needed
                            if let snapshot = rowVisibilitySnapshot {
                                let currentShowTaxes = item.effectiveShowTaxesGoalRow
                                let currentIsTaxEnabled = item.isTaxSavingsEnabled
                                let currentShowReallocations = item.effectiveShowReallocationsRow
                                let currentShowSurplus = item.effectiveShowIncomeSurplusRow
                                
                                // Check if the effective visibility of the taxes row changed
                                // (either the show toggle OR the tax enabled state)
                                let wasShowingTaxes = snapshot.isTaxEnabled && snapshot.showTaxes
                                let isShowingTaxes = currentIsTaxEnabled && currentShowTaxes
                                
                                if wasShowingTaxes != isShowingTaxes ||
                                   snapshot.showReallocations != currentShowReallocations ||
                                   snapshot.showSurplus != currentShowSurplus {
                                    // Row visibility changed - scroll to current month
                                    scrollToCurrentMonthCounter += 1
                                }
                            }
                            
                            // Clear the snapshot
                            rowVisibilitySnapshot = nil
                        },
                        onCancel: {
                            showingEditDetails = false
                            // No need to revert - BudgetDetailsView handles this internally
                            
                            // Clear the snapshot
                            rowVisibilitySnapshot = nil
                        }
                    )
                }
                .standardSheetPresentation()
                .onAppear {
                    // Capture row visibility snapshot when sheet appears
                    rowVisibilitySnapshot = (
                        showTaxes: item.effectiveShowTaxesGoalRow,
                        isTaxEnabled: item.isTaxSavingsEnabled,
                        showReallocations: item.effectiveShowReallocationsRow,
                        showSurplus: item.effectiveShowIncomeSurplusRow
                    )
                }
            }
            .sheet(isPresented: $showingIncomeView) {
                BudgetIncomeSheetView(item: item, incomes: $incomes, attachments: $attachments) { yearMonth in
                    showingIncomeView = false
                    navigationPath?.wrappedValue.append(yearMonth)
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(expenses: $expenses, selectedMonth: nil, selectedYear: nil, selectedDay: nil, item: item)
                    .standardSheetPresentation()
            }
            .sheet(isPresented: $showingAddIncome) {
                AddIncomeView(incomes: $incomes, item: item, showRecurringOption: true, defaultShowDate: true, showMonthSelector: false, selectedMonth: nil, selectedYear: nil, selectedDay: nil)
                    .standardSheetPresentation()
            }
            .sheet(isPresented: $showingReallocateFunds) {
                ReallocateFundsView(reallocations: $reallocations, expenses: $expenses, incomes: $incomes, item: item, selectedMonth: nil, selectedYear: nil)
                    .standardSheetPresentation()
            }
            .sheet(item: $expenseToEdit) { expense in
                if let expenseBinding = SafeBindingHelper.binding(for: expense, in: $expenses) {
                    EditExpenseView(expense: expenseBinding, expenses: $expenses, item: item)
                        .standardSheetPresentation()
                } else {
                    Text("Expense not found")
                        .onAppear {
                            expenseToEdit = nil
                        }
                }
            }
            .sheet(item: $incomeToEdit) { income in
                if let incomeBinding = SafeBindingHelper.binding(for: income, in: $incomes) {
                    EditIncomeView(income: incomeBinding, incomes: $incomes, item: item)
                        .standardSheetPresentation()
                } else {
                    Text("Income not found")
                        .onAppear {
                            incomeToEdit = nil
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
                month: Date().month,
                year: Date().year
            )
    }
    
    // MARK: - Toolbar Content Builders
    
    @ToolbarContentBuilder
    private var principalToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(item.displayName)
                .font(.headline)
                .lineLimit(1)
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSelecting {
                // Selection mode: Show Cancel, Select All, and Done buttons
                let totalItems = expenses.count + incomes.count + reallocations.count + attachments.count
                let totalSelected = selectedExpenses.count + selectedIncomes.count + selectedReallocations.count + selectedAttachments.count
                let selectAllText = totalSelected == 0 ? "Select All" : (totalSelected == totalItems ? "Deselect All" : "Select All")
                HStack {
                    Button {
                        exitSelectionMode()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .tint(.primary)
                    
                    Button {
                        if totalSelected == totalItems {
                            selectedExpenses.removeAll()
                            selectedIncomes.removeAll()
                            selectedReallocations.removeAll()
                            selectedAttachments.removeAll()
                        } else {
                            selectedExpenses = Set(expenses.map(\.id))
                            selectedIncomes = Set(incomes.map(\.id))
                            selectedReallocations = Set(reallocations.map(\.id))
                            selectedAttachments = Set(attachments.map(\.id))
                        }
                    } label: {
                        Label(selectAllText, systemImage: totalSelected == totalItems ? "checklist.unchecked" : "checklist.checked")
                    }
                    .tint(.primary)
                    .id("budgetSelectAll")
                    
                    Button {
                        exitSelectionMode()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .tint(.primary)
                }
            } else {
                // Normal mode: Show year picker
                let currentYear = Date().year
                let startYear = currentYear - 24
                
                Menu {
                    Picker(selection: $selectedYear) {
                        ForEach((startYear...currentYear).reversed(), id: \.self) { year in
                            Text(String(year))
                                .tag(year)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(selectedYear), systemImage: "calendar")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                }
                .tint(.primary)
                .id("yearSelector-\(item.id)")
            }
        }
    }
    
    @ToolbarContentBuilder
    private var bottomBarToolbarItem: some ToolbarContent {
        if !isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    scrollToCurrentMonthCounter += 1
                } label: {
                    Label("Current Month", systemImage: "calendar.badge.clock")
                }
                .tint(.primary)
                .id("budgetJumpToCurrentMonth-\(item.id)")

                Button {
                    showingIncomeView = true
                } label: {
                    Label("Year Overview", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tint(.primary)
                .id("budgetIncomeView-\(item.id)")

                Button {
                    showingEditDetails = true
                } label: {
                    Label("Edit Details", systemImage: "square.and.pencil")
                }
                .tint(.primary)
                .id("budgetEditDetails-\(item.id)")

                Spacer()

                Button {
                    selectedYear -= 1
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .tint(.primary)

                Button {
                    selectedYear += 1
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
                .id("budgetAddMenu-\(item.id)")
            }
        }
    }
    
    var body: some View {
        mainFormView
            .navigationDestination(for: YearMonth.self) { yearMonth in
                MonthDetailsPageView(yearMonth: yearMonth, item: item)
                    .onAppear {
                        NavigationStateManager.shared.saveCurrentYearMonth(yearMonth)
                        NavigationStateManager.shared.viewedYearMonth = yearMonth
                    }
            }
            .toolbar {
                principalToolbarItem
                trailingToolbarItem
                bottomBarToolbarItem
            }
            .toolbarRole(.automatic)
        .background {
            sheetsModifier
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert("Delete Selected Items?", isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete", role: .destructive) {
                            removeSelectedItems()
                        }
                    } message: {
                        let totalSelected = selectedExpenses.count + selectedIncomes.count
                        let itemText = totalSelected == 1 ? "item" : "items"
                        Text("This will permanently delete \(totalSelected) \(itemText). This action cannot be undone.")
                    }
            }
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert(
                        "Funds Auto-Reallocated",
                        isPresented: Binding(
                            get: { autoReallocationAlert != nil },
                            set: { if !$0 { autoReallocationAlert = nil } }
                        ),
                        presenting: autoReallocationAlert
                    ) { _ in
                        Button("OK") { autoReallocationAlert = nil }
                    } message: { summary in
                        Text(reallocationAlertMessage(summary))
                    }
            }
        }
        .onAppear {
            // Set initial load flag before loading data
            isInitialLoad = true
            
            // Load budget data FIRST to prevent flash of zeros
            loadBudgetData()
            
            item.lastOpenedDate = Date()
            if let context = item.modelContext {
                do {
                    try context.save()
                    print("💾 BudgetVisualizerPageView: Saved lastOpenedDate update")
                } catch {
                    print("❌ BudgetVisualizerPageView: Error saving lastOpenedDate - \(error)")
                }
            }
            
            if !didInitialAppear {
                didInitialAppear = true
                if let targetYear = item.targetYear {
                    selectedYear = targetYear
                }
            }
            // body.onAppear fires AFTER mainFormView.onAppear during navigation pop
            // (inner views become visible first). mainFormView.onAppear already handled
            // the scroll but intentionally left viewedYearMonth set so we can read it
            // here to correct selectedYear, which may have just been reset to the old
            // saved year by the item.targetYear block above.
            if let target = NavigationStateManager.shared.viewedYearMonth {
                NavigationStateManager.shared.viewedYearMonth = nil
                if selectedYear != target.year {
                    selectedYear = target.year
                    // item.targetYear must also be updated — onChange(of: selectedYear)
                    // won't fire if mainFormView.onAppear already set selectedYear to
                    // the same value (no net change from SwiftUI's perspective).
                    item.targetYear = target.year
                    try? item.modelContext?.save()
                }
            }
        }
        .onChange(of: showingEditDetails) { oldValue, newValue in
            if !newValue {
                if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    item.name = "Budget Visualizer"
                }
                // No need to persist here - onChange handlers will catch any changes
            }
        }
        .onBudgetDataChange(
            expenses: expenses, incomes: incomes,
            attachments: attachments, reallocations: reallocations,
            isInitialLoad: isInitialLoad, persist: { persistBudgetData() }
        )
        .onChange(of: selectedYear) { oldValue, newValue in
            item.targetYear = newValue
            
            if let context = item.modelContext {
                do {
                    try context.save()
                    print("💾 BudgetVisualizerPageView: Saved targetYear change to \(newValue)")
                } catch {
                    print("❌ BudgetVisualizerPageView: Error saving targetYear - \(error)")
                }
            }
        }
        .onChange(of: attachments) { old, new in
            guard !isInitialLoad, new.count > old.count else { return }
            let now = Date()
            let ym = YearMonth(year: now.year, month: now.month)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToCurrentMonthCounter += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.default) { highlightedHeaderYearMonth = ym }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.default) { highlightedHeaderYearMonth = nil }
                }
            }
        }
        // Proactively switch selectedYear whenever viewedYearMonth changes (fires even while
        // MonthDetailsPageView is on top, because @Observable tracking establishes a
        // subscription via the onChange value expression read during body evaluation).
        .onChange(of: NavigationStateManager.shared.viewedYearMonth) { _, newValue in
            guard let target = newValue else { return }
            if selectedYear != target.year {
                pendingScrollYearMonth = target
                pendingScrollAnimated = false
                selectedYear = target.year
            }
        }
        .onCategoryRenamed(expenses: $expenses, incomes: $incomes)
    }

    /// Loads all budget data (expenses, incomes, attachments, reallocations) from the item's encoded data
    /// Decodes JSON data and populates the local state arrays
    private func loadBudgetData() {
        guard let data = item.decodeBudgetData() else { isInitialLoad = false; return }
        expenses = data.expenses; incomes = data.incomes
        attachments = data.attachments; reallocations = data.reallocations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInitialLoad = false
            print("✅ Initial load complete - persistence enabled")
            autoReallocateExcessFunds()
        }
    }

    /// Removes all auto-generated reallocations, then creates new ones from every previous month
    /// that has a positive surplus, routing all excess to the current calendar month.
    private func autoReallocateExcessFunds() {
        let now = Date()
        let currentMonth = now.month
        let currentYear = now.year

        // Snapshot existing auto-reallocations before clearing so we can detect changes
        let previousAutoEntries = reallocations.filter { $0.isAutoGenerated && $0.isFromEntry }

        // Clear every auto-generated reallocation so we start fresh each load
        let autoIDs = Set(reallocations.filter { $0.isAutoGenerated }.map { $0.id })
        if !autoIDs.isEmpty {
            reallocations.removeAll { autoIDs.contains($0.id) }
        }

        // Determine the earliest year that has any income or expense data
        let allDates = incomes.map(\.date) + expenses.map(\.date)
        guard let earliestDate = allDates.min() else {
            if !autoIDs.isEmpty { persistBudgetData() }
            return
        }
        let startYear = earliestDate.year

        let calendar = Calendar.current
        var newReallocations: [Reallocation] = []

        for year in startYear...currentYear {
            let maxMonth = (year == currentYear) ? currentMonth - 1 : 12
            guard maxMonth >= 1 else { continue }
            for month in 1...maxMonth {
                let available = computeAvailableFundsInFromMonth(
                    incomes: incomes,
                    expenses: expenses,
                    reallocations: reallocations,
                    fromMonth: month, fromYear: year,
                    toMonth: currentMonth, toYear: currentYear,
                    item: item
                )
                guard available.isEffectivelyPositive else { continue }

                let fromId = UUID()
                let toId = UUID()

                // "from" entry date: last day of the source month at 23:59
                let fromDate: Date
                if let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                   let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
                   let lastDayStart = calendar.date(byAdding: .day, value: -1, to: nextMonthStart) {
                    let comps = calendar.dateComponents([.year, .month, .day], from: lastDayStart)
                    fromDate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 23, minute: 59)) ?? lastDayStart
                } else {
                    fromDate = now
                }

                // "to" entry date: first day of the current month at 00:00
                let toDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: 1, hour: 0, minute: 0)) ?? now

                newReallocations.append(Reallocation(
                    id: fromId, linkedId: toId,
                    amount: available,
                    fromMonth: month, fromYear: year,
                    toMonth: currentMonth, toYear: currentYear,
                    isFromEntry: true,
                    date: fromDate, createdAt: now,
                    isAutoGenerated: true
                ))
                newReallocations.append(Reallocation(
                    id: toId, linkedId: fromId,
                    amount: available,
                    fromMonth: month, fromYear: year,
                    toMonth: currentMonth, toYear: currentYear,
                    isFromEntry: false,
                    date: toDate, createdAt: now,
                    isAutoGenerated: true
                ))
            }
        }

        if !newReallocations.isEmpty || !autoIDs.isEmpty {
            reallocations.append(contentsOf: newReallocations)
            persistBudgetData()

            if !newReallocations.isEmpty {
                let sources = newReallocations
                    .filter { $0.isFromEntry }
                    .map { (month: $0.fromMonth, year: $0.fromYear, amount: $0.amount) }

                // Only alert when the reallocated months or amounts actually changed
                let previousKeys = Set(previousAutoEntries.map { "\($0.fromMonth)-\($0.fromYear)-\($0.amount)" })
                let newKeys = Set(sources.map { "\($0.month)-\($0.year)-\($0.amount)" })
                if newKeys != previousKeys {
                    let totalAmount = sources.map { $0.amount }.sumMoney()
                    autoReallocationAlert = AutoReallocationSummary(
                        totalAmount: totalAmount,
                        sources: sources,
                        toMonth: currentMonth,
                        toYear: currentYear
                    )
                }
            }
        }
    }

    private func reallocationAlertMessage(_ summary: AutoReallocationSummary) -> String {
        let toName = "\(monthDisplayName(summary.toMonth)) \(summary.toYear)"
        let totalStr = summary.totalAmount.formatted(.currency(code: selectedCurrency.code))
        var lines = ["\(totalStr) moved to \(toName)", ""]
        for source in summary.sources {
            let fromName = "\(monthDisplayName(source.month)) \(source.year)"
            let amtStr = source.amount.formatted(.currency(code: selectedCurrency.code))
            lines.append("\(amtStr) from \(fromName)")
        }
        return lines.joined(separator: "\n")
    }

    private func persistBudgetData() {
        saveBudgetData(to: item, expenses: expenses, incomes: incomes,
                       attachments: attachments, reallocations: reallocations)
    }

    /// Removes an expense from the budget and persists the change
    private func removeExpense(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        persistBudgetData()
    }
    
    /// Removes an income from the budget and persists the change
    private func removeIncome(_ income: Income) {
        incomes.removeAll { $0.id == income.id }
        persistBudgetData()
    }
    
    /// Creates a duplicate of an expense with all its properties
    /// Adds the duplicate to the expenses array and persists
    private func copyExpense(_ expense: Expense) {
        expenses.append(expense.duplicate())
        persistBudgetData()
    }
    
    private func payOffExpense(_ expense: Expense) {
        incomes.append(makeIncomeFromExpense(expense))
        persistBudgetData()
    }

    /// Creates a duplicate of an income with all its properties
    /// Adds the duplicate to the incomes array and persists
    private func copyIncome(_ income: Income) {
        incomes.append(income.duplicate())
        persistBudgetData()
    }
    
    private func exitSelectionMode() {
        isSelecting = false
        selectedExpenses.removeAll()
        selectedIncomes.removeAll()
        selectedReallocations.removeAll()
        selectedAttachments.removeAll()
    }

    /// Toggles the selection state of an expense
    private func toggleExpenseSelectionState(for expense: Expense) {
        selectedExpenses.toggle(expense.id)
    }
    
    /// Toggles the selection state of an income
    private func toggleIncomeSelectionState(for income: Income) {
        selectedIncomes.toggle(income.id)
    }
    
    /// Removes all selected items (expenses, incomes, reallocations, attachments)
    /// For reallocations, removes both entries in the linked pair
    /// Clears selection state and exits selection mode
    private func removeSelectedItems() {
        expenses.removeAll { selectedExpenses.contains($0.id) }
        incomes.removeAll { selectedIncomes.contains($0.id) }
        // Delete reallocations and their linked pairs
        for reallocationID in selectedReallocations {
            if let reallocation = reallocations.first(where: { $0.id == reallocationID }) {
                reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
            }
        }
        // Delete attachments
        attachments.removeAll { selectedAttachments.contains($0.id) }
        
        exitSelectionMode()
        persistBudgetData()
    }
    
}
private struct YearMonthHeaderRowView: View {
    let yearMonth: YearMonth
    let highlightColor: Color
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        let now = Date()
        let isCurrentMonth = (yearMonth.year == now.year && yearMonth.month == now.month)

        HStack(alignment: .center) {
            Text(yearMonth.displayName)
                .fontWeight(.medium)
                .foregroundStyle(isHighlighted ? highlightColor : .primary)
            if isCurrentMonth {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                    .foregroundStyle(highlightColor)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .animation(.default, value: isHighlighted)
    }
}

