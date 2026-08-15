//
//  ReallocationViews.swift
//  Bookee
//
//  Views for creating and editing fund reallocations between months.
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Reallocation Footer Text

/// Reusable footer text for reallocation views
private struct ReallocationFooterText: View {
    let amount: Double
    let availableFunds: Double
    let fromMonth: Int
    let fromYear: Int
    let toMonth: Int
    let toYear: Int
    let selectedCurrency: Currency
    
    var body: some View {
        if (amount - availableFunds).isEffectivelyPositive {
            Text("The reallocation amount exceeds the available funds in \(monthDisplayName(fromMonth)) \(String(fromYear)). You can only reallocate \(availableFunds, format: .currency(code: selectedCurrency.code)).")
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            Text("Tap 'Available Funds' or 'Needed To Break Even' rows to set the 'Amount' to those values. The 'Amount' will be limited to available funds.")
                .font(.footnote)
        }
    }
}

// MARK: - Reallocation Month Selection Section

/// Shared date picker section used by both ReallocateFundsView and EditReallocateFundsView.
private struct ReallocationMonthSelectionSection: View {
    @Binding var fromDate: Date
    @Binding var toDate: Date

    var body: some View {
        Section {
            HStack {
                Text("From")
                Spacer()
                DatePicker("", selection: $fromDate, displayedComponents: .date)
                    .labelsHidden()
                DatePicker("", selection: $fromDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            HStack {
                Text("Add To")
                Spacer()
                DatePicker("", selection: $toDate, displayedComponents: .date)
                    .labelsHidden()
                DatePicker("", selection: $toDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Shared Reallocation Calculations

/// Computes the break-even income amount needed in the "to" month.
/// Correctly counts multiple occurrences of weekly/bi-weekly recurring items per month.
/// Pass `excludingIDs` when editing an existing pair so the current entries are not double-counted.
private func computeBreakEvenAmount(
    incomes: [Income], expenses: [Expense], reallocations: [Reallocation],
    toMonth: Int, toYear: Int,
    item: Item, excludingIDs: Set<UUID> = []
) -> Double {
    let incomeAmounts: [(amount: Double, isTaxable: Bool)] = incomes.compactMap { income in
        guard let amount = effectiveMonthlyAmount(for: income, month: toMonth, year: toYear) else { return nil }
        return (amount, income.isTaxable)
    }
    let totalTaxableIncome = incomeAmounts.filter { $0.isTaxable }.map { $0.amount }.sumMoney()
    let totalUntaxableIncome = incomeAmounts.filter { !$0.isTaxable }.map { $0.amount }.sumMoney()

    let totalExpenses = expenses.compactMap { effectiveMonthlyAmount(for: $0, month: toMonth, year: toYear) }.sumMoney()

    let existingReallocation = reallocations.additionsIn(yearMonth: YearMonth(year: toYear, month: toMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()
    let totalExistingUntaxable = roundMoney(totalUntaxableIncome + existingReallocation)

    return breakEvenDeficit(
        taxableIncome: totalTaxableIncome,
        untaxableIncome: totalExistingUntaxable,
        expenses: totalExpenses,
        isTaxActive: item.isTaxActive,
        taxRate: item.taxRate
    )
}

// MARK: - Reallocation Details Section

/// Shared Amount / Available Funds / Break-Even section used by both
/// ReallocateFundsView and EditReallocateFundsView.
private struct ReallocationDetailsSection: View {
    @Binding var amount: Double
    let availableFunds: Double
    let breakEven: Double
    let fromMonth: Int
    let fromYear: Int
    let toMonth: Int
    let toYear: Int
    let selectedCurrency: Currency

    @FocusState private var isAmountFocused: Bool
    @AppStorage("showFooters") private var showFooters: Bool = true

    var body: some View {
        Section {
            HStack {
                Text("Amount")
                Spacer()
                CalculatorStyleCurrencyTextField(
                    amount: $amount,
                    isFocused: $isAmountFocused
                ) {
                    isAmountFocused = false
                }
                .frame(width: 125)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { isAmountFocused = true }

            HStack {
                Text("Available Funds")
                Spacer()
                Text(availableFunds, format: .currency(code: selectedCurrency.code))
                    .foregroundStyle((amount - availableFunds).isEffectivelyPositive ? .red : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isAmountFocused else { return }
                amount = availableFunds
            }

            HStack {
                Text("Needed To Break Even")
                Spacer()
                Text(breakEven, format: .currency(code: selectedCurrency.code))
                    .foregroundStyle(breakEven.isEffectivelyPositive ? .green : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isAmountFocused else { return }
                amount = breakEven
            }
        } header: {
            Text("Reallocation Details")
        } footer: {
            if showFooters {
                ReallocationFooterText(
                    amount: amount,
                    availableFunds: availableFunds,
                    fromMonth: fromMonth,
                    fromYear: fromYear,
                    toMonth: toMonth,
                    toYear: toYear,
                    selectedCurrency: selectedCurrency
                )
            }
        }
    }
}

// MARK: - Reallocate Funds View

/// View for creating a new reallocation between two months
/// Creates paired entries: one negative (From) and one positive (add to)
struct ReallocateFundsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var reallocations: [Reallocation]
    @Binding var expenses: [Expense]
    @Binding var incomes: [Income]
    var item: Item

    @State private var amount: Double = 0.0
    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var attachments: [Attachment] = []
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd

    // For pre-selecting a specific month when opened from month details
    var selectedMonth: Int?
    var selectedYear: Int?
    
    private var fromMonth: Int { fromDate.month }
    private var fromYear: Int { fromDate.year }
    private var toMonth: Int { toDate.month }
    private var toYear: Int { toDate.year }

    init(reallocations: Binding<[Reallocation]>, expenses: Binding<[Expense]>, incomes: Binding<[Income]>, item: Item, selectedMonth: Int? = nil, selectedYear: Int? = nil) {
        self._reallocations = reallocations
        self._expenses = expenses
        self._incomes = incomes
        self.item = item
        self.selectedMonth = selectedMonth
        self.selectedYear = selectedYear
        
        let calendar = Calendar.current
        let now = Date()
        
        // Initialize dates based on selected month or current date
        if let month = selectedMonth, let year = selectedYear {
            let currentYear = now.year
            let currentMonth = now.month
            let currentDay = now.day
            
            // Get current time components
            let timeComponents = calendar.dateComponents([.hour, .minute], from: now)
            
            // Determine which day to use
            let dayToUse: Int
            if year == currentYear && month == currentMonth {
                // Current month - use today's day
                dayToUse = currentDay
            } else if year < currentYear || (year == currentYear && month < currentMonth) {
                // Past month - use last day of month
                // Get the range of days in this month to find the last day
                let tempDate = calendar.firstOfMonth(month: month, year: year) ?? now
                if let range = calendar.range(of: .day, in: .month, for: tempDate) {
                    dayToUse = range.count
                } else {
                    dayToUse = 1
                }
            } else {
                // Future month - use first of month
                dayToUse = 1
            }
            
            // Create date with selected month/year/day and current time
            var components = DateComponents(year: year, month: month, day: dayToUse)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            if let monthDate = calendar.date(from: components) {
                self._fromDate = State(initialValue: monthDate)
                self._toDate = State(initialValue: monthDate)
            } else {
                self._fromDate = State(initialValue: now)
                self._toDate = State(initialValue: now)
            }
        } else {
            self._fromDate = State(initialValue: now)
            self._toDate = State(initialValue: now)
        }
    }
    
    private var availableFundsInFromMonth: Double {
        computeAvailableFundsInFromMonth(incomes: incomes, expenses: expenses, reallocations: reallocations, fromMonth: fromMonth, fromYear: fromYear, toMonth: toMonth, toYear: toYear, item: item)
    }

    private var breakEvenUntaxableIncome: Double {
        computeBreakEvenAmount(incomes: incomes, expenses: expenses, reallocations: reallocations, toMonth: toMonth, toYear: toYear, item: item)
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                monthSelectionSection

                AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Reallocate Funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(dismiss: dismiss)

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addReallocation) {
                        Label("Add", systemImage: "plus")
                    }
                    .tint(.primary)
                    .disabled(!amount.isEffectivelyPositive || (amount - availableFundsInFromMonth).isEffectivelyPositive || (fromMonth == toMonth && fromYear == toYear))
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    AttachmentMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker)
                }
            }
            .sheet(item: $attachmentToView) { attachment in
                AttachmentViewerSheet(attachment: attachment)
            }
            .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments)
        }
    }
    
    private var detailsSection: some View {
        ReallocationDetailsSection(
            amount: $amount,
            availableFunds: availableFundsInFromMonth,
            breakEven: breakEvenUntaxableIncome,
            fromMonth: fromMonth, fromYear: fromYear,
            toMonth: toMonth, toYear: toYear,
            selectedCurrency: selectedCurrency
        )
    }
    
    private var monthSelectionSection: some View {
        ReallocationMonthSelectionSection(fromDate: $fromDate, toDate: $toDate)
    }

    private func addReallocation() {
        // Create paired reallocation entries
        // Titles are now generated automatically from month/year data when displayed
        let fromId = UUID()
        let toId = UUID()
        
        // Create "from" entry (subtracts from the month)
        // The date parameter is used for sorting, so it should match the fromDate
        let fromEntry = Reallocation(
            id: fromId,
            linkedId: toId,
            amount: amount.roundedMoney(),
            fromMonth: fromMonth,
            fromYear: fromYear,
            toMonth: toMonth,
            toYear: toYear,
            isFromEntry: true,
            date: fromDate,
            createdAt: fromDate,
            attachments: attachments
        )

        // Create "to" entry (adds to the month)
        // The date parameter is used for sorting, so it should match the toDate
        let toEntry = Reallocation(
            id: toId,
            linkedId: fromId,
            amount: amount.roundedMoney(),
            fromMonth: fromMonth,
            fromYear: fromYear,
            toMonth: toMonth,
            toYear: toYear,
            isFromEntry: false,
            date: toDate,
            createdAt: toDate
        )
        
        reallocations.append(fromEntry)
        reallocations.append(toEntry)
        dismiss()
    }
}

// MARK: - Edit Reallocate Funds View

struct EditReallocateFundsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var reallocation: Reallocation
    @Binding var reallocations: [Reallocation]
    @Binding var expenses: [Expense]
    @Binding var incomes: [Income]
    var item: Item

    @State private var amount: Double
    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var attachments: [Attachment]
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Track original values for change detection
    @State private var originalAmount: Double
    @State private var originalFromDate: Date
    @State private var originalToDate: Date
    @State private var showingDeleteConfirmation = false

    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    private var fromMonth: Int { fromDate.month }
    private var fromYear: Int { fromDate.year }
    private var toMonth: Int { toDate.month }
    private var toYear: Int { toDate.year }

    init(reallocation: Binding<Reallocation>, reallocations: Binding<[Reallocation]>, expenses: Binding<[Expense]>, incomes: Binding<[Income]>, item: Item) {
        self._reallocation = reallocation
        self._reallocations = reallocations
        self._expenses = expenses
        self._incomes = incomes
        self.item = item
        
        // Initialize state with current reallocation values to prevent flickering
        let currentReallocation = reallocation.wrappedValue
        
        // Find the linked reallocation to get the other date
        let linkedReallocation = reallocations.wrappedValue.first(where: { $0.id == currentReallocation.linkedId })
        
        // Determine which dates to use based on whether this is a "from" or "to" entry
        if currentReallocation.isFromEntry {
            // This is the "from" entry - use its date directly for fromDate
            self._fromDate = State(initialValue: currentReallocation.date)
            
            // For toDate, use the linked entry's date if available, otherwise fallback to constructing from month/year
            if let linked = linkedReallocation {
                self._toDate = State(initialValue: linked.date)
                self._originalToDate = State(initialValue: linked.date)
            } else {
                // Fallback: construct from month/year
                let calendar = Calendar.current
                let toDateComponents = DateComponents(
                    year: currentReallocation.toYear,
                    month: currentReallocation.toMonth,
                    day: calendar.component(.day, from: currentReallocation.date),
                    hour: calendar.component(.hour, from: currentReallocation.date),
                    minute: calendar.component(.minute, from: currentReallocation.date)
                )
                let initialToDate = calendar.date(from: toDateComponents) ?? currentReallocation.date
                self._toDate = State(initialValue: initialToDate)
                self._originalToDate = State(initialValue: initialToDate)
            }
            
            self._originalFromDate = State(initialValue: currentReallocation.date)
        } else {
            // This is the "to" entry - use its date directly for toDate
            self._toDate = State(initialValue: currentReallocation.date)
            
            // For fromDate, use the linked entry's date if available, otherwise fallback to constructing from month/year
            if let linked = linkedReallocation {
                self._fromDate = State(initialValue: linked.date)
                self._originalFromDate = State(initialValue: linked.date)
            } else {
                // Fallback: construct from month/year
                let calendar = Calendar.current
                let fromDateComponents = DateComponents(
                    year: currentReallocation.fromYear,
                    month: currentReallocation.fromMonth,
                    day: calendar.component(.day, from: currentReallocation.date),
                    hour: calendar.component(.hour, from: currentReallocation.date),
                    minute: calendar.component(.minute, from: currentReallocation.date)
                )
                let initialFromDate = calendar.date(from: fromDateComponents) ?? currentReallocation.date
                self._fromDate = State(initialValue: initialFromDate)
                self._originalFromDate = State(initialValue: initialFromDate)
            }
            
            self._originalToDate = State(initialValue: currentReallocation.date)
        }
        
        self._amount = State(initialValue: currentReallocation.amount)
        self._attachments = State(initialValue: currentReallocation.attachments)

        // Store original amount
        self._originalAmount = State(initialValue: currentReallocation.amount)
    }
    
    private var availableFundsInFromMonth: Double {
        computeAvailableFundsInFromMonth(incomes: incomes, expenses: expenses, reallocations: reallocations, fromMonth: fromMonth, fromYear: fromYear, toMonth: toMonth, toYear: toYear, item: item, excludingIDs: [reallocation.id, reallocation.linkedId])
    }

    private var breakEvenUntaxableIncome: Double {
        computeBreakEvenAmount(incomes: incomes, expenses: expenses, reallocations: reallocations, toMonth: toMonth, toYear: toYear, item: item, excludingIDs: [reallocation.id, reallocation.linkedId])
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                monthSelectionSection

                AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Edit Reallocation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(dismiss: dismiss)

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveReallocation) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .tint(.primary)
                    .disabled(!amount.isEffectivelyPositive || (amount - availableFundsInFromMonth).isEffectivelyPositive || (fromMonth == toMonth && fromYear == toYear))
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                    Spacer()
                    AttachmentMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker)
                }
            }
            .sheet(item: $attachmentToView) { attachment in
                AttachmentViewerSheet(attachment: attachment)
            }
            .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments)
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert("Delete Reallocation?", isPresented: $showingDeleteConfirmation) {
                        Button("Delete", role: .destructive) { performDeleteReallocation() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete this reallocation. This action cannot be undone.")
                    }
            }
        }
    }
    
    private var detailsSection: some View {
        ReallocationDetailsSection(
            amount: $amount,
            availableFunds: availableFundsInFromMonth,
            breakEven: breakEvenUntaxableIncome,
            fromMonth: fromMonth, fromYear: fromYear,
            toMonth: toMonth, toYear: toYear,
            selectedCurrency: selectedCurrency
        )
    }
    
    private var monthSelectionSection: some View {
        ReallocationMonthSelectionSection(fromDate: $fromDate, toDate: $toDate)
    }

    private func saveReallocation() {
        // Find the linked reallocation to determine which is "from" and which is "to"
        if let linkedIndex = reallocations.firstIndex(where: { $0.id == reallocation.linkedId }) {
            // Titles are now generated automatically from month/year data when displayed
            // No need to update title properties
            
            // Update both the current reallocation and its linked pair
            reallocation.amount = amount.roundedMoney()
            reallocation.fromMonth = fromMonth
            reallocation.fromYear = fromYear
            reallocation.toMonth = toMonth
            reallocation.toYear = toYear
            
            // Update both date and createdAt based on which entry this is
            // The date field is used for sorting, so it must match the month it represents
            if reallocation.isFromEntry {
                reallocation.date = fromDate
                reallocation.createdAt = fromDate
                reallocations[linkedIndex].date = toDate
                reallocations[linkedIndex].createdAt = toDate
            } else {
                reallocation.date = toDate
                reallocation.createdAt = toDate
                reallocations[linkedIndex].date = fromDate
                reallocations[linkedIndex].createdAt = fromDate
            }
            
            reallocations[linkedIndex].amount = amount.roundedMoney()
            reallocations[linkedIndex].fromMonth = fromMonth
            reallocations[linkedIndex].fromYear = fromYear
            reallocations[linkedIndex].toMonth = toMonth
            reallocations[linkedIndex].toYear = toYear
        }
        
        reallocation.attachments = attachments

        // Check for changes before creating backup
        let hasChanges = !amount.isEffectivelyEqual(to: originalAmount) ||
                        fromDate != originalFromDate ||
                        toDate != originalToDate
        
        if hasChanges {
            print("✅ EditReallocateFundsView: Changes saved for reallocation")
        } else {
            print("⏭️ EditReallocateFundsView: No changes detected, skipping save")
        }
        
        dismiss()
    }

    private func performDeleteReallocation() {
        reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
        dismiss()
    }
}


