//
//  ReallocationViews.swift
//  Bookee
//
//  Views for creating and editing fund reallocations between months.
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Reallocation Month Selection Section

/// Shared month/year picker section used by both ReallocateFundsView and EditReallocateFundsView.
private struct ReallocationMonthSelectionSection: View {
    @Binding var fromDate: Date
    @Binding var toDate: Date

    private let calendar = Calendar.current
    private let thisYear = Calendar.current.component(.year, from: Date())

    var body: some View {
        Section {
            monthYearRow(label: "From", date: $fromDate)
            monthYearRow(label: "Add To", date: $toDate)
        }
    }

    @ViewBuilder
    private func monthYearRow(label: String, date: Binding<Date>) -> some View {
        HStack {
            Text(label)
            Spacer()
            monthMenu(date: date)
            yearMenu(date: date)
        }
    }

    @ViewBuilder
    private func monthMenu(date: Binding<Date>) -> some View {
        let selectedMonth = calendar.component(.month, from: date.wrappedValue)
        Menu {
            Picker(selection: Binding(
                get: { calendar.component(.month, from: date.wrappedValue) },
                set: { newMonth in
                    let year = calendar.component(.year, from: date.wrappedValue)
                    if let d = calendar.date(from: DateComponents(year: year, month: newMonth, day: 1)) {
                        date.wrappedValue = d
                    }
                }
            )) {
                ForEach(1...12, id: \.self) { month in
                    Text(monthDisplayName(month)).tag(month)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            Text(monthDisplayName(selectedMonth))
        }
        .tint(.primary)
    }

    @ViewBuilder
    private func yearMenu(date: Binding<Date>) -> some View {
        let selectedYear = calendar.component(.year, from: date.wrappedValue)
        Menu {
            Picker(selection: Binding(
                get: { calendar.component(.year, from: date.wrappedValue) },
                set: { newYear in
                    let month = calendar.component(.month, from: date.wrappedValue)
                    if let d = calendar.date(from: DateComponents(year: newYear, month: month, day: 1)) {
                        date.wrappedValue = d
                    }
                }
            )) {
                ForEach(((thisYear - 10)...(thisYear + 2)).reversed(), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            Text(String(selectedYear))
        }
        .tint(.primary)
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
) -> Decimal {
    let activeIncomes = incomes.filter { $0.deletedDate == nil }
    let incomeAmounts: [(income: Income, amount: Decimal)] = activeIncomes.compactMap { income in
        guard let amount = effectiveMonthlyAmount(for: income, month: toMonth, year: toYear) else { return nil }
        return (income, amount)
    }
    let totalTaxableIncome = incomeAmounts.filter { $0.income.isTaxable }.map { $0.amount }.sumMoney()
    let totalUntaxableIncome = incomeAmounts.filter { !$0.income.isTaxable }.map { $0.amount }.sumMoney()

    let totalExpenses = expenses.filter { $0.deletedDate == nil }.compactMap { effectiveMonthlyAmount(for: $0, month: toMonth, year: toYear) }.sumMoney()

    let existingReallocationAdditions = reallocations.additionsIn(yearMonth: YearMonth(year: toYear, month: toMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()
    let existingReallocationDeductions = reallocations.deductionsIn(yearMonth: YearMonth(year: toYear, month: toMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()
    let totalExistingUntaxable = roundMoney(totalUntaxableIncome + existingReallocationAdditions - existingReallocationDeductions)

    if item.isTaxActive {
        let tax = TaxDistributionHelper.distributedTaxAmounts(for: incomeAmounts, defaultPercentage: item.taxSavingsPercentage).values.sumMoney()
        let afterTax = roundMoney(totalTaxableIncome - tax)
        let available = roundMoney(afterTax + totalExistingUntaxable)
        return max(0, roundMoney(totalExpenses - available))
    } else {
        let totalIncome = roundMoney(totalTaxableIncome + totalExistingUntaxable)
        return max(0, roundMoney(totalExpenses - totalIncome))
    }
}

// MARK: - Reallocation Details Section

/// Shared Amount / Available Funds / Break-Even section used by both
/// ReallocateFundsView and EditReallocateFundsView.
private struct ReallocationDetailsSection: View {
    @Binding var amount: Decimal
    let availableFunds: Decimal
    let breakEven: Decimal
    let selectedCurrency: Currency

    @FocusState private var isAmountFocused: Bool
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
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .textCase(nil)
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

    @State private var amount: Decimal = 0
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
    // Set by the presenter when restoring a saved `.addReallocation` subpage, so this
    // instance reopens with whatever the user had entered rather than a blank form.
    // Consumed and cleared on first appear.
    var initialDraft: Binding<ReallocationFormDraft?> = .constant(nil)

    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    private var fromMonth: Int { fromDate.month }
    private var fromYear: Int { fromDate.year }
    private var toMonth: Int { toDate.month }
    private var toYear: Int { toDate.year }

    init(reallocations: Binding<[Reallocation]>, expenses: Binding<[Expense]>, incomes: Binding<[Income]>, item: Item, selectedMonth: Int? = nil, selectedYear: Int? = nil, initialDraft: Binding<ReallocationFormDraft?> = .constant(nil)) {
        self._reallocations = reallocations
        self._expenses = expenses
        self._incomes = incomes
        self.item = item
        self.selectedMonth = selectedMonth
        self.selectedYear = selectedYear
        self.initialDraft = initialDraft

        if let draft = initialDraft.wrappedValue {
            self._amount = State(initialValue: draft.amount)
            self._fromDate = State(initialValue: draft.fromDate)
            self._toDate = State(initialValue: draft.toDate)
            self._attachments = State(initialValue: draft.attachments)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            let now = Date()
            let month = selectedMonth ?? now.month
            let year  = selectedYear  ?? now.year
            let first = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
            self._fromDate = State(initialValue: first)
            self._toDate   = State(initialValue: first)
        }
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress form survives the app being terminated.
    private var draftSnapshot: ReallocationFormDraft {
        ReallocationFormDraft(amount: amount, fromDate: fromDate, toDate: toDate, attachments: attachments, viewingAttachmentID: attachmentToView?.id)
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.reallocation(snapshot), for: timestamp)
        }
    }

    private var availableFundsInFromMonth: Decimal {
        computeAvailableFundsInFromMonth(incomes: incomes, expenses: expenses, reallocations: reallocations, fromMonth: fromMonth, fromYear: fromYear, toMonth: toMonth, toYear: toYear, item: item)
    }

    private var breakEvenUntaxableIncome: Decimal {
        computeBreakEvenAmount(incomes: incomes, expenses: expenses, reallocations: reallocations, toMonth: toMonth, toYear: toYear, item: item)
    }

    var body: some View {
        Form {
            detailsSection
            monthSelectionSection

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    draftSaveTask?.cancel()
                    NavigationStateManager.shared.clearDraft()
                    dismiss()
                } label: {
                    Label("Reallocation", systemImage: "arrow.left.arrow.right")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .tint(.primary)
            }

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
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if initialDraft.wrappedValue != nil {
                initialDraft.wrappedValue = nil
            } else {
                // A fresh (non-restored) open — clear any draft abandoned by a previous
                // attempt so it's never mistakenly picked up by an unrelated new one.
                NavigationStateManager.shared.clearDraft()
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .navigationDestination(item: $attachmentToView) { attachment in
            AttachmentViewerSheet(attachment: attachment)
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments)
    }
    
    private var detailsSection: some View {
        ReallocationDetailsSection(
            amount: $amount,
            availableFunds: availableFundsInFromMonth,
            breakEven: breakEvenUntaxableIncome,
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
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
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

    @State private var amount: Decimal
    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var attachments: [Attachment]
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Track original values for change detection
    @State private var originalAmount: Decimal
    @State private var originalFromDate: Date
    @State private var originalToDate: Date
    @State private var showingDeleteConfirmation = false

    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd

    // Set by the presenter when restoring a saved in-progress edit (including its nested
    // attachment viewer, if one was open), so this instance reopens with whatever the user
    // had changed rather than the saved reallocation's original values. Consumed and cleared
    // on first appear.
    var initialDraft: Binding<ReallocationFormDraft?> = .constant(nil)
    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    private var fromMonth: Int { fromDate.month }
    private var fromYear: Int { fromDate.year }
    private var toMonth: Int { toDate.month }
    private var toYear: Int { toDate.year }

    init(reallocation: Binding<Reallocation>, reallocations: Binding<[Reallocation]>, expenses: Binding<[Expense]>, incomes: Binding<[Income]>, item: Item, initialDraft: Binding<ReallocationFormDraft?> = .constant(nil)) {
        self._reallocation = reallocation
        self._reallocations = reallocations
        self._expenses = expenses
        self._incomes = incomes
        self.item = item
        self.initialDraft = initialDraft

        // Original values are always anchored to the true model, regardless of a restored
        // draft, since change detection must compare against what's actually saved.
        let current = reallocation.wrappedValue
        let cal = Calendar.current
        let fromFirst = cal.date(from: DateComponents(year: current.fromYear, month: current.fromMonth, day: 1)) ?? current.date
        let toFirst   = cal.date(from: DateComponents(year: current.toYear,   month: current.toMonth,   day: 1)) ?? current.date
        self._originalFromDate = State(initialValue: fromFirst)
        self._originalToDate   = State(initialValue: toFirst)
        self._originalAmount   = State(initialValue: current.amount)

        if let draft = initialDraft.wrappedValue {
            self._amount      = State(initialValue: draft.amount)
            self._fromDate     = State(initialValue: draft.fromDate)
            self._toDate       = State(initialValue: draft.toDate)
            self._attachments = State(initialValue: draft.attachments)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            self._fromDate    = State(initialValue: fromFirst)
            self._toDate      = State(initialValue: toFirst)
            self._amount      = State(initialValue: current.amount)
            self._attachments = State(initialValue: current.attachments)
        }
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress edit survives the app being terminated.
    private var draftSnapshot: ReallocationFormDraft {
        ReallocationFormDraft(amount: amount, fromDate: fromDate, toDate: toDate, attachments: attachments, viewingAttachmentID: attachmentToView?.id)
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.reallocation(snapshot), for: timestamp)
        }
    }
    
    private var availableFundsInFromMonth: Decimal {
        computeAvailableFundsInFromMonth(incomes: incomes, expenses: expenses, reallocations: reallocations, fromMonth: fromMonth, fromYear: fromYear, toMonth: toMonth, toYear: toYear, item: item, excludingIDs: [reallocation.id, reallocation.linkedId])
    }

    private var breakEvenUntaxableIncome: Decimal {
        computeBreakEvenAmount(incomes: incomes, expenses: expenses, reallocations: reallocations, toMonth: toMonth, toYear: toYear, item: item, excludingIDs: [reallocation.id, reallocation.linkedId])
    }

    var body: some View {
        Form {
            detailsSection
            monthSelectionSection

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    draftSaveTask?.cancel()
                    NavigationStateManager.shared.clearDraft()
                    dismiss()
                } label: {
                    Label("Reallocation", systemImage: "arrow.left.arrow.right")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .tint(.primary)
            }

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
        .navigationDestination(item: $attachmentToView) { attachment in
            AttachmentViewerSheet(attachment: attachment)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if initialDraft.wrappedValue != nil {
                initialDraft.wrappedValue = nil
            } else {
                // A fresh (non-restored) open — clear any draft abandoned by a previous
                // attempt so it's never mistakenly picked up by an unrelated new one.
                NavigationStateManager.shared.clearDraft()
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments)
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
            selectedCurrency: selectedCurrency
        )
    }
    
    private var monthSelectionSection: some View {
        ReallocationMonthSelectionSection(fromDate: $fromDate, toDate: $toDate)
    }

    private func saveReallocation() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
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
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
        dismiss()
    }

}


