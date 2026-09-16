//
//  AddEditViews.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Shared Recurring Occurrence Utilities

/// Returns true when a recurring item with the given frequency has only a single occurrence
/// between `startDate` and `endDate`.
private func hasOnlyOneOccurrence(startDate: Date, endDate: Date?, frequencyRawValue: String, rule: RecurrenceRule? = nil) -> Bool {
    let calendar = Calendar.current
    guard let endDate = endDate else { return false }
    if calendar.isDate(startDate, inSameDayAs: endDate) { return true }
    if let rule = rule {
        let next = rule.nextOccurrence(after: startDate, startDate: startDate)
        if let next = next { return next > endDate }
        return false
    }
    let nextOccurrence: Date?
    switch frequencyRawValue {
    case "Daily":    nextOccurrence = calendar.date(byAdding: .day,        value: 1,  to: startDate)
    case "Weekly":   nextOccurrence = calendar.date(byAdding: .weekOfYear, value: 1,  to: startDate)
    case "Bi-weekly":nextOccurrence = calendar.date(byAdding: .weekOfYear, value: 2,  to: startDate)
    case "Monthly":  nextOccurrence = calendar.date(byAdding: .month,      value: 1,  to: startDate)
    case "Quarterly":nextOccurrence = calendar.date(byAdding: .month,      value: 3,  to: startDate)
    case "Yearly":   nextOccurrence = calendar.date(byAdding: .year,       value: 1,  to: startDate)
    default:         nextOccurrence = nil
    }
    if let next = nextOccurrence { return next > endDate }
    return false
}

// MARK: - Shared Attachment Loading

/// Loads photos from picker results into a generic Attachment binding.
/// Completion is called on the main actor after each attachment is appended.
func loadPhotoAttachments(from results: [PHPickerResult], into attachments: Binding<[Attachment]>, onComplete: @escaping () -> Void = {}) async {
    for result in results {
        loadImageData(from: result) { data in
            let attachment = Attachment(data: data, fileName: makePhotoFileName(), fileType: .image)
            Task { @MainActor in
                attachments.wrappedValue.append(attachment)
                onComplete()
            }
        }
    }
}

/// Loads a document from a security-scoped URL into a generic Attachment binding.
func loadDocumentAttachment(from url: URL, into attachments: Binding<[Attachment]>, onComplete: @escaping () -> Void = {}) {
    guard let (data, fileName, fileType) = loadFileData(from: url) else { return }
    let attachment = Attachment(data: data, fileName: fileName, fileType: fileType)
    attachments.wrappedValue.append(attachment)
    onComplete()
}

// MARK: - Shared Payment Plan Utilities

/// Calculates the per-payment amount for a payment plan using floor (cents-down) division.
/// Delegates to `floorCentsPerPayment` in MoneyUtilities.swift.
private func calculatePaymentAmount(total: Decimal, payments: Int) -> Decimal? {
    floorCentsPerPayment(total: total, payments: payments)
}

/// Calculates the end date of a payment plan given start date, frequency, and payment count.
private func calculateEndDate(from startDate: Date, frequency: RecurringFrequency, payments: Int) -> Date {
    let calendar = Calendar.current
    let component: Calendar.Component
    let value: Int
    switch frequency {
    case .daily:    component = .day;        value = payments - 1
    case .weekly:   component = .weekOfYear; value = payments - 1
    case .biweekly: component = .weekOfYear; value = (payments - 1) * 2
    case .monthly:  component = .month;      value = payments - 1
    case .quarterly:component = .month;      value = (payments - 1) * 3
    case .yearly:   component = .year;       value = payments - 1
    }
    return calendar.date(byAdding: component, value: value, to: startDate) ?? startDate
}

// MARK: - Shared Name Default Helper

/// Returns `name` trimmed, or `fallback` if the trimmed result is empty.
private func defaultName(_ name: String, fallback: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : name
}

// MARK: - Sort-Order Array Insert

extension Array {
    /// Inserts at index 0 in manual sort mode; appends otherwise.
    mutating func insert(_ element: Element, forSortOrder sortOrder: SortOrder) {
        if sortOrder == .manual { insert(element, at: 0) } else { append(element) }
    }
}

// MARK: - Shared Attachment Comparison

/// Returns true when two attachment arrays have the same IDs in the same order.
/// Used by edit views to detect whether attachments changed.
private func attachmentsSameByID(_ a: [Attachment], _ b: [Attachment]) -> Bool {
    guard a.count == b.count else { return false }
    return zip(a, b).allSatisfy { $0.id == $1.id }
}

// MARK: - Shared Edited-Time Helper

/// Returns `baseDate`'s calendar day with the hour/minute taken from `editedDate`.
/// Used when splitting a recurring item to preserve the user's chosen time.
private func mergeEditedTime(from editedDate: Date, intoDay baseDate: Date) -> Date {
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.year, .month, .day], from: baseDate)
    comps.hour = calendar.component(.hour, from: editedDate)
    comps.minute = calendar.component(.minute, from: editedDate)
    return calendar.date(from: comps) ?? baseDate
}

// MARK: - Generic Recurring-Edit Helper

/// Applies a recurring-edit scope to a typed item in `items`, splitting or updating as needed.
/// Returns `true` when the caller should fall back to "save all" (no modifications were made);
/// returns `false` when the split was applied and the caller should dismiss.
///
/// - Parameters:
///   - scope: The edit scope chosen by the user (.all, .currentAndFuture, .currentOnly).
///   - items: The full array of recurring items (mutated in place on a successful split).
///   - itemID: The ID of the item being edited.
///   - occurrenceDate: The specific occurrence tapped by the user (nil = use item's start date).
///   - itemDate: The item's original start date (fallback when occurrenceDate is nil).
///   - editedDate: The new date entered by the user (hour/minute used for time-merge).
///   - createEdited: Closure that builds the fully-edited version of the item.
///   - onOneTimeCreated: Called on the one-time copy before it is appended (e.g. to clear isMonthlyPaymentPlan).
@discardableResult
private func applyRecurringItemEdit<T: RecurringItem>(
    scope: RecurringScope,
    items: inout [T],
    itemID: UUID,
    occurrenceDate: Date?,
    itemDate: Date,
    editedDate: Date,
    createEdited: () -> T,
    onOneTimeCreated: (inout T) -> Void = { _ in }
) -> Bool {
    let calendar = Calendar.current
    let occurrenceDateNorm = calendar.startOfDay(for: occurrenceDate ?? itemDate)
    guard let index = items.firstIndex(where: { $0.id == itemID }) else { return true }
    let orig = items[index]
    guard let normalizedStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: orig.date)) else { return true }
    let frequency = orig.effectiveFrequency
    let rule = orig.resolvedRule

    switch scope {
    case .all:
        return true

    case .currentAndFuture:
        if occurrenceDateNorm == normalizedStart { return true }
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: occurrenceDateNorm)!
        var truncated = orig
        truncated.endDate = dayBefore
        truncated.showEndDate = true
        items[index] = truncated
        var newItem = createEdited()
        newItem.date = mergeEditedTime(from: editedDate, intoDay: occurrenceDateNorm)
        items.append(newItem)

    case .currentOnly:
        let nextOcc = findNextOccurrence(after: occurrenceDateNorm, startDate: normalizedStart, frequency: frequency, rule: rule)
        if occurrenceDateNorm == normalizedStart {
            if let end = orig.endDate, nextOcc > end { return true }
            var updated = orig
            updated.date = nextOcc
            items[index] = updated
        } else {
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: occurrenceDateNorm)!
            var before = orig
            before.endDate = dayBefore
            before.showEndDate = true
            items[index] = before
            let shouldCreateAfter = orig.endDate.map { nextOcc <= $0 } ?? true
            if shouldCreateAfter {
                var afterItem = orig.duplicate()
                afterItem.date = nextOcc
                items.append(afterItem)
            }
        }
        var oneTime = createEdited()
        oneTime.date = mergeEditedTime(from: editedDate, intoDay: occurrenceDateNorm)
        oneTime.endDate = oneTime.date
        oneTime.showEndDate = true
        onOneTimeCreated(&oneTime)
        items.append(oneTime)
    }
    return false
}

// MARK: - Shared Date Initialization Helper

/// Computes the initial date for Add views from month/year/day context or defaults to now.
/// Priority: defaultDate > selectedMonth/Year/Day > current date
func computeInitialDate(selectedMonth: Int?, selectedYear: Int?, selectedDay: Int?, defaultDate: Date?) -> Date {
    let now = Date()
    if let provided = defaultDate { return provided }
    guard let month = selectedMonth, let year = selectedYear else { return now }
    let calendar = Calendar.current
    if let day = selectedDay {
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        var comps = DateComponents(year: year, month: month, day: day)
        comps.hour = time.hour; comps.minute = time.minute; comps.second = time.second
        return calendar.date(from: comps) ?? now
    }
    if year == now.year && month == now.month { return now }
    return calendar.firstOfMonth(month: month, year: year) ?? now
}

// MARK: - Shared Attachment Picker Modifier

extension View {
    /// Attaches the photo-picker sheet and file-importer to the view, delegating attachment loading.
    func attachmentPickers(
        showingPhotoPicker: Binding<Bool>,
        showingFilePicker: Binding<Bool>,
        attachments: Binding<[Attachment]>,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        self
            .sheet(isPresented: showingPhotoPicker) {
                PhotoPickerRepresentable { results in
                    Task {
                        await loadPhotoAttachments(from: results, into: attachments) {
                            onDismiss()
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: showingFilePicker,
                allowedContentTypes: [.pdf, .text, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadDocumentAttachment(from: url, into: attachments) {
                            onDismiss()
                        }
                    }
                case .failure(let error):
                    print("❌ Error selecting file: \(error)")
                }
            }
    }
}

// MARK: - Category Picker Button

/// Reusable category selection row used by all Add/Edit Income and Expense views.
struct CategoryPickerButton: View {
    let selectedCategories: Set<String>
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Category")
                Spacer()
                let displayText = selectedCategories.contains(SettingsDefault.uncategorizedSentinel)
                    ? "Uncategorized"
                    : selectedCategories.sorted().joined(separator: ", ")
                if !displayText.isEmpty {
                    Text(displayText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Attachment Menu Button

/// Reusable paperclip toolbar button shared by Add/Edit Income and Expense views.
struct AttachmentMenuButton: View {
    @Binding var showingPhotoPicker: Bool
    @Binding var showingFilePicker: Bool
    var onMenuTap: (() -> Void)?

    var body: some View {
        Menu {
            Button { showingPhotoPicker = true } label: { Label("Photo", systemImage: "photo") }.tint(.primary)
            Button { showingFilePicker = true } label: { Label("File",  systemImage: "doc")   }.tint(.primary)
        } label: {
            Label("Attachment", systemImage: "paperclip")
        }
        .simultaneousGesture(TapGesture().onEnded { onMenuTap?() })
        .tint(.primary)
    }
}

// MARK: - Payment Plan Bindings

struct PaymentPlanBindings {
    let isEnabled: Binding<Bool>
    let numberOfPayments: Binding<Int>
    let amount: Binding<Decimal>
    let endDate: Binding<Date>
    let totalAmount: Decimal
    let recurringFrequency: RecurringFrequency
    let currencyCode: String
}

// MARK: - Frequency Option

private enum FrequencyOption: Hashable {
    case oneTime
    case recurring(RecurrenceUnit)
}

// MARK: - Recurring Picker Rows

/// Inline frequency rows for add/edit sheets: payment plan toggle (optional), frequency menu
/// (One Time + recurring units), and interval stepper. Place inside a Section in the Form.
struct RecurringPickerRows: View {
    @Binding var rule: RecurrenceRule
    @Binding var isRecurring: Bool
    let startDate: Date
    var paymentPlan: PaymentPlanBindings? = nil

    var body: some View {
        Group {
            Picker("Frequency", selection: frequencyBinding) {
                Text("Daily").tag(FrequencyOption.recurring(.day))
                Text("Weekly").tag(FrequencyOption.recurring(.week))
                Text("Monthly").tag(FrequencyOption.recurring(.month))
                Text("Yearly").tag(FrequencyOption.recurring(.year))
                Divider()
                Text("One Time").tag(FrequencyOption.oneTime)
            }
            .pickerStyle(.menu)

            if isRecurring {
                Stepper(value: $rule.interval, in: 1...99) {
                    Text(intervalLabel)
                }
            }

            RecurringExtraSections(rule: $rule, isRecurring: isRecurring)
        }
    }

    private var frequencyBinding: Binding<FrequencyOption> {
        Binding(
            get: { isRecurring ? .recurring(rule.unit) : .oneTime },
            set: { option in
                switch option {
                case .oneTime:
                    isRecurring = false
                    paymentPlan?.isEnabled.wrappedValue = false
                case .recurring(let unit):
                    isRecurring = true
                    rule.unit = unit
                    if unit == .week && rule.weekdays.isEmpty {
                        rule.weekdays = Set([Calendar.current.component(.weekday, from: startDate)])
                    }
                    if unit == .month && rule.monthDays.isEmpty {
                        rule.monthDays = [Calendar.current.component(.day, from: startDate)]
                    }
                }
            }
        )
    }

    private var intervalLabel: String {
        let n = rule.interval
        switch rule.unit {
        case .day:   return n == 1 ? "Every Day"   : "Every \(n) Days"
        case .week:  return n == 1 ? "Every Week"  : "Every \(n) Weeks"
        case .month: return n == 1 ? "Every Month" : "Every \(n) Months"
        case .year:  return n == 1 ? "Every Year"  : "Every \(n) Years"
        }
    }
}

// MARK: - Recurring Extra Rows

/// Weekday selector for Weekly, and day-of-month grid for Monthly. Rendered inside the main options Section.
struct RecurringExtraSections: View {
    @Binding var rule: RecurrenceRule
    let isRecurring: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let isWeekly = isRecurring && rule.unit == .week
        let isMonthly = isRecurring && rule.unit == .month
        let symbols = Calendar.current.veryShortWeekdaySymbols

        Group {
            // Weekday circles (Weekly)
            if isWeekly {
                HStack(spacing: 0) {
                    ForEach(1...7, id: \.self) { wd in
                        let selected = rule.weekdays.contains(wd)
                        Button {
                            if rule.weekdays.contains(wd) {
                                if rule.weekdays.count > 1 { rule.weekdays.remove(wd) }
                            } else {
                                rule.weekdays.insert(wd)
                            }
                        } label: {
                            Text(symbols[wd - 1])
                                .font(.body)
                                .fontWeight(selected ? .bold : .medium)
                                .frame(minWidth: 38, minHeight: 38)
                                .frame(maxWidth: .infinity)
                                .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, -7)
            }

            // Day-of-month grid (Monthly)
            if isMonthly {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(1...31, id: \.self) { day in
                        let selected = rule.monthDays.contains(day)
                        Button {
                            if rule.monthDays.contains(day) {
                                if rule.monthDays.count > 1 { rule.monthDays.remove(day) }
                            } else {
                                rule.monthDays.insert(day)
                            }
                        } label: {
                            Text("\(day)")
                                .font(.body)
                                .fontWeight(selected ? .bold : .medium)
                                .frame(minWidth: 38, minHeight: 38)
                                .frame(maxWidth: .infinity)
                                .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    let lastSelected = rule.monthDays.contains(32)
                    Button {
                        if rule.monthDays.contains(32) {
                            if rule.monthDays.count > 1 { rule.monthDays.remove(32) }
                        } else {
                            rule.monthDays.insert(32)
                        }
                    } label: {
                        Text("LD")
                            .font(.body)
                            .fontWeight(lastSelected ? .bold : .medium)
                            .frame(minWidth: 38, minHeight: 38)
                            .frame(maxWidth: .infinity)
                            .background(lastSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(lastSelected ? Color.white : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, -7)
            }
        }
    }
}

// MARK: - Payment Amount Row

/// Read-only row showing the calculated per-payment amount for a payment plan.
struct PaymentAmountRow: View {
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        HStack {
            Text("Payment")
            Spacer()
            Text(amount, format: .currency(code: currencyCode))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Number Of Payments Picker

/// Picker for selecting the number of payments in a monthly payment plan.
struct NumberOfPaymentsPicker: View {
    @Binding var numberOfPayments: Int
    @Binding var endDate: Date
    let date: Date
    let recurringFrequency: RecurringFrequency
    var isEnabled: Bool = true

    var body: some View {
        if isEnabled {
            Stepper(value: $numberOfPayments, in: 2...999) {
                Text("\(numberOfPayments) Payments")
            }
            .onChange(of: numberOfPayments) { _, _ in
                endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
            }
        }
    }
}

// MARK: - Add Expense View

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var expenses: [Expense]
    @Binding var incomes: [Income]
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd

    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var date: Date
    @State private var showDate = false
    @State private var endDate: Date
    @State private var showEndDate = false
    @State private var isRecurring = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    @State private var recurrenceRule: RecurrenceRule = RecurrenceRule(legacy: .monthly)

    // Payment plan properties (expense-only)
    @State private var isMonthlyPaymentPlan = false
    @State private var totalAmount: Decimal = 0
    @State private var numberOfPayments: Int = 12

    // Income-only properties
    @State private var isTaxable = true

    // Type picker
    @State private var itemType: AddItemType

    // Attachment properties
    @State private var attachments: [Attachment] = []
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Category properties
    @State private var selectedCategories: Set<String> = [SettingsDefault.uncategorizedSentinel]
    @State private var showingCategoryPicker = false

    // Month/year context when adding expense from a specific month view
    // Used to restrict date picker ranges to the selected month
    var selectedMonth: Int?
    var selectedYear: Int?
    var selectedDay: Int?
    var defaultDate: Date?
    var item: Item?
    var initialType: AddItemType
    // Set by the presenter when restoring a saved `.addExpense`/`.addIncome` subpage, so this
    // instance reopens with whatever the user had typed rather than a blank form. Consumed
    // and cleared on first appear.
    var initialDraft: Binding<TransactionFormDraft?> = .constant(nil)

    enum Field: Hashable {
        case name
        case amount
        case totalAmount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isTotalAmountFocused: Bool
    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    init(expenses: Binding<[Expense]>, incomes: Binding<[Income]> = .constant([]), selectedMonth: Int? = nil, selectedYear: Int? = nil, selectedDay: Int? = nil, defaultDate: Date? = nil, item: Item? = nil, initialType: AddItemType = .expense, initialDraft: Binding<TransactionFormDraft?> = .constant(nil)) {
        self._expenses = expenses
        self._incomes = incomes
        self.selectedMonth = selectedMonth
        self.selectedYear = selectedYear
        self.selectedDay = selectedDay
        self.defaultDate = defaultDate
        self.item = item
        self.initialType = initialType
        self.initialDraft = initialDraft

        if let draft = initialDraft.wrappedValue {
            self._itemType = State(initialValue: draft.itemType)
            self._name = State(initialValue: draft.name)
            self._amount = State(initialValue: draft.amount)
            self._date = State(initialValue: draft.date)
            self._showDate = State(initialValue: draft.showDate)
            self._endDate = State(initialValue: draft.endDate)
            self._showEndDate = State(initialValue: draft.showEndDate)
            self._isRecurring = State(initialValue: draft.isRecurring)
            self._recurringFrequency = State(initialValue: draft.recurringFrequency)
            self._recurrenceRule = State(initialValue: draft.recurrenceRule)
            self._isMonthlyPaymentPlan = State(initialValue: draft.isMonthlyPaymentPlan)
            self._totalAmount = State(initialValue: draft.totalAmount)
            self._numberOfPayments = State(initialValue: draft.numberOfPayments)
            self._isTaxable = State(initialValue: draft.isTaxable)
            self._attachments = State(initialValue: draft.attachments)
            self._selectedCategories = State(initialValue: draft.selectedCategories)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            self._itemType = State(initialValue: initialType)
            let initialDate = computeInitialDate(selectedMonth: selectedMonth, selectedYear: selectedYear, selectedDay: selectedDay, defaultDate: defaultDate)
            self._date = State(initialValue: initialDate)
            self._endDate = State(initialValue: initialDate)
        }
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress form survives the app being terminated.
    private var draftSnapshot: TransactionFormDraft {
        TransactionFormDraft(
            name: name, amount: amount, date: date, showDate: showDate, endDate: endDate,
            showEndDate: showEndDate, isRecurring: isRecurring, recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule, isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: totalAmount, numberOfPayments: numberOfPayments, isTaxable: isTaxable,
            itemType: itemType, attachments: attachments, selectedCategories: selectedCategories,
            pickerSelectedMonth: nil, viewingAttachmentID: attachmentToView?.id
        )
    }

    private func scheduleDraftSave() {
        guard let item else { return }
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.expenseOrIncome(snapshot), for: timestamp)
        }
    }
    
    var body: some View {
        Form {
            detailsSection
            optionsSection

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationDestination(isPresented: $showingCategoryPicker) {
            if let item {
                CategoryPickerView(selectedCategories: $selectedCategories, item: item, month: selectedMonth ?? Calendar.current.component(.month, from: Date()), year: selectedYear ?? Calendar.current.component(.year, from: Date()))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ItemTypePickerToolbarItem(itemType: $itemType, types: [.expense, .income])

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: saveItem) {
                    Label("Add", systemImage: "plus")
                }
                .tint(.primary)
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                AttachmentMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker) {
                    dismissKeyboard()
                }
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                focusedField = .name

                if initialDraft.wrappedValue != nil {
                    initialDraft.wrappedValue = nil
                } else if item != nil {
                    // A fresh (non-restored) open — clear any draft abandoned by a previous
                    // attempt so it's never mistakenly picked up by an unrelated new one.
                    NavigationStateManager.shared.clearDraft()
                }
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .navigationDestination(item: $attachmentToView) { attachment in
            AttachmentViewerSheet(attachment: attachment)
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
            dismissKeyboard()
        }
    }

    private var detailsSection: some View {
        Section {
            HStack {
                Text("Title")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $name, placeholder: "Expense") {
                    // On return, move focus to the appropriate amount field
                    if isMonthlyPaymentPlan {
                        isTotalAmountFocused = true
                    } else {
                        isAmountFocused = true
                    }
                }
                .multilineTextAlignment(.trailing)
                .dismissKeyboardOnReturn(false)
                .focused($focusedField, equals: .name)
                .textInputAutocapitalization(.words)
                .onChange(of: focusedField) { oldValue, newValue in
                    if oldValue == .name && newValue != .name {
                        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .name
            }
            
            // Amount field label changes based on payment plan mode
            // Payment plan: shows "Total Amount" and binds to totalAmount
            // Regular expense: shows "Amount" and binds to amount
            HStack {
                Text(isMonthlyPaymentPlan ? "Total" : "Amount")
                Spacer()
                CalculatorStyleCurrencyTextField(
                    amount: isMonthlyPaymentPlan ? $totalAmount : $amount,
                    isFocused: isMonthlyPaymentPlan ? $isTotalAmountFocused : $isAmountFocused
                ) {
                    // Dismiss keyboard on return
                    isAmountFocused = false
                    isTotalAmountFocused = false
                }
                .frame(width: 125)
                .lineLimit(1)
                .onChange(of: totalAmount) { _, _ in
                    if isMonthlyPaymentPlan {
                        endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isMonthlyPaymentPlan {
                    isTotalAmountFocused = true
                } else {
                    isAmountFocused = true
                }
            }
            .id("mainAmountField") // Stable identity
            
            if itemType == .expense && isMonthlyPaymentPlan {
                PaymentAmountRow(amount: calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? 0, currencyCode: selectedCurrency.code)
            }

            CategoryPickerButton(selectedCategories: selectedCategories) {
                dismissKeyboard()
                guard item != nil else { return }
                showingCategoryPicker = true
            }

            if itemType == .income, let item, item.isTaxSavingsEnabled {
                Toggle("Taxable", isOn: $isTaxable)
            }

            if itemType == .expense {
                Toggle("Payment Plan", isOn: $isMonthlyPaymentPlan)
            }
        } header: {
            Text(itemType == .income ? "Income Details" : "Expense Details")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }

    private var optionsSection: some View {
        Section {
            // Date picker - label changes based on mode
            // In recurring/payment plan mode: "Start Date"
            // In one-time mode: "Date"
            HStack {
                Text(isRecurring || isMonthlyPaymentPlan ? "Start Date" : "Date")
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: date) { _, newValue in
                    if showEndDate && !isMonthlyPaymentPlan && endDate < newValue { endDate = newValue }
                    if isMonthlyPaymentPlan { endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments) }
                }
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            RecurringPickerRows(
                rule: $recurrenceRule,
                isRecurring: $isRecurring,
                startDate: date,
                paymentPlan: itemType == .expense ? PaymentPlanBindings(
                    isEnabled: $isMonthlyPaymentPlan,
                    numberOfPayments: $numberOfPayments,
                    amount: $amount,
                    endDate: $endDate,
                    totalAmount: totalAmount,
                    recurringFrequency: recurringFrequency,
                    currencyCode: selectedCurrency.code
                ) : nil
            )
            .onChange(of: recurrenceRule) { _, newRule in
                recurringFrequency = newRule.closestLegacyFrequency
                if isMonthlyPaymentPlan {
                    endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
                }
            }
            .onChange(of: isRecurring) { _, newValue in
                if newValue && !isMonthlyPaymentPlan {
                    showDate = true
                } else if !isMonthlyPaymentPlan {
                    showDate = false
                    showEndDate = false
                }
            }
            .onChange(of: isMonthlyPaymentPlan) { _, newValue in
                if newValue {
                    isRecurring = true
                    showDate = true
                    showEndDate = true
                    if totalAmount.isEffectivelyZero && amount.isEffectivelyPositive {
                        totalAmount = amount
                    }
                    endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
                } else {
                    isRecurring = false
                    showDate = false
                    showEndDate = false
                }
            }

            if itemType == .expense {
                NumberOfPaymentsPicker(
                    numberOfPayments: $numberOfPayments,
                    endDate: $endDate,
                    date: date,
                    recurringFrequency: recurringFrequency,
                    isEnabled: isMonthlyPaymentPlan
                )
            }

            if isRecurring && !(itemType == .expense && isMonthlyPaymentPlan) {
                Toggle("End Date", isOn: $showEndDate)
            }

            if showEndDate && isRecurring {
                HStack {
                    Text("End Date")
                    Spacer()
                    DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                        .labelsHidden()
                        .disabled(itemType == .expense && isMonthlyPaymentPlan)
                    DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(itemType == .expense && isMonthlyPaymentPlan)
                }
            }

        }
    }

    /// Dismisses both SwiftUI and UIKit keyboards
    private func dismissKeyboard() {
        focusedField = nil
        // Send resign action to UIKit responder chain for custom text fields
        resignKeyboard()
    }

    private func saveItem() {
        switch itemType {
        case .expense: addExpense()
        case .income: addIncome()
        case .reallocation: break
        }
    }

    private func addIncome() {
        let newIncome = Income(
            name: defaultName(name, fallback: "Income"),
            amount: amount.roundedMoney(),
            date: date,
            showDate: showDate,
            endDate: showEndDate ? endDate : nil,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments,
            isTaxable: isTaxable,
            taxPercentageOverride: nil,
            categories: selectedCategories.sorted()
        )
        incomes.insert(newIncome, forSortOrder: sortOrder)
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        dismiss()
    }

    /// Creates and adds the expense to the array
    private func addExpense() {
        let finalAmount: Decimal
        let finalTotalAmount: Decimal?

        // In payment plan mode, use calculated payment; otherwise use entered amount
        if isMonthlyPaymentPlan {
            // Use calculated payment
            finalAmount = calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? totalAmount.roundedMoney()
            finalTotalAmount = totalAmount.roundedMoney()
        } else {
            finalAmount = amount.roundedMoney()
            finalTotalAmount = nil
        }

        let finalShowDate = !isRecurring || showDate
        let newExpense = Expense(
            name: defaultName(name, fallback: "Expense"),
            amount: finalAmount,
            date: date,
            showDate: finalShowDate,
            endDate: (isMonthlyPaymentPlan || showEndDate) ? endDate : nil,
            showEndDate: isMonthlyPaymentPlan || showEndDate,
            isRecurring: isMonthlyPaymentPlan || isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: isMonthlyPaymentPlan ? nil : recurrenceRule,
            isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: finalTotalAmount,
            attachments: attachments,
            categories: selectedCategories.sorted()
        )
        expenses.insert(newExpense, forSortOrder: sortOrder)

        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        dismiss()
    }

}

// MARK: - Add Income View

struct AddIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var incomes: [Income]
    @Binding var expenses: [Expense]
    var item: Item
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd

    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var date: Date
    @State private var showDate: Bool
    @State private var endDate: Date
    @State private var showEndDate = false
    @State private var isRecurring = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    @State private var recurrenceRule: RecurrenceRule = RecurrenceRule(legacy: .monthly)
    @State private var pickerSelectedMonth: Int
    @State private var attachments: [Attachment] = []
    @State private var attachmentToView: Attachment?
    @State private var isTaxable = true
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Expense-only properties
    @State private var isMonthlyPaymentPlan = false
    @State private var totalAmount: Decimal = 0
    @State private var numberOfPayments: Int = 12

    // Type picker
    @State private var itemType: AddItemType = .income

    // Category properties
    @State private var selectedCategories: Set<String> = [SettingsDefault.uncategorizedSentinel]
    @State private var showingCategoryPicker = false

    enum Field: Hashable {
        case name
        case amount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool
    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    var showRecurringOption: Bool = true
    var defaultShowDate: Bool = false
    var showMonthSelector: Bool = false

    // Date range restriction for budget page
    var budgetSelectedMonth: Int?
    var budgetSelectedYear: Int?
    var budgetSelectedDay: Int?
    var defaultDate: Date?
    // Set by the presenter when restoring a saved `.addIncome` subpage, so this instance
    // reopens with whatever the user had typed rather than a blank form. Consumed and
    // cleared on first appear.
    var initialDraft: Binding<TransactionFormDraft?> = .constant(nil)

    init(incomes: Binding<[Income]>, expenses: Binding<[Expense]> = .constant([]), item: Item, showRecurringOption: Bool = true, defaultShowDate: Bool = false, showMonthSelector: Bool = false, selectedMonth: Int? = nil, selectedYear: Int? = nil, selectedDay: Int? = nil, defaultDate: Date? = nil, initialDraft: Binding<TransactionFormDraft?> = .constant(nil)) {
        self._incomes = incomes
        self._expenses = expenses
        self.item = item
        self.showRecurringOption = showRecurringOption
        self.defaultShowDate = defaultShowDate
        self.showMonthSelector = showMonthSelector
        self.budgetSelectedMonth = selectedMonth
        self.budgetSelectedYear = selectedYear
        self.budgetSelectedDay = selectedDay
        self.defaultDate = defaultDate
        self.initialDraft = initialDraft

        if let draft = initialDraft.wrappedValue {
            self._itemType = State(initialValue: draft.itemType)
            self._name = State(initialValue: draft.name)
            self._amount = State(initialValue: draft.amount)
            self._date = State(initialValue: draft.date)
            self._showDate = State(initialValue: draft.showDate)
            self._endDate = State(initialValue: draft.endDate)
            self._showEndDate = State(initialValue: draft.showEndDate)
            self._isRecurring = State(initialValue: draft.isRecurring)
            self._recurringFrequency = State(initialValue: draft.recurringFrequency)
            self._recurrenceRule = State(initialValue: draft.recurrenceRule)
            self._isMonthlyPaymentPlan = State(initialValue: draft.isMonthlyPaymentPlan)
            self._totalAmount = State(initialValue: draft.totalAmount)
            self._numberOfPayments = State(initialValue: draft.numberOfPayments)
            self._isTaxable = State(initialValue: draft.isTaxable)
            self._attachments = State(initialValue: draft.attachments)
            self._selectedCategories = State(initialValue: draft.selectedCategories)
            self._pickerSelectedMonth = State(initialValue: draft.pickerSelectedMonth ?? Date().month)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            self._showDate = State(initialValue: defaultShowDate)
            self._pickerSelectedMonth = State(initialValue: Date().month)
            // When showMonthSelector is active, skip month-context date computation
            let initialDate = computeInitialDate(
                selectedMonth: showMonthSelector ? nil : selectedMonth,
                selectedYear: showMonthSelector ? nil : selectedYear,
                selectedDay: showMonthSelector ? nil : selectedDay,
                defaultDate: defaultDate
            )
            self._date = State(initialValue: initialDate)
            self._endDate = State(initialValue: initialDate)
        }
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress form survives the app being terminated.
    private var draftSnapshot: TransactionFormDraft {
        TransactionFormDraft(
            name: name, amount: amount, date: date, showDate: showDate, endDate: endDate,
            showEndDate: showEndDate, isRecurring: isRecurring, recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule, isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: totalAmount, numberOfPayments: numberOfPayments, isTaxable: isTaxable,
            itemType: itemType, attachments: attachments, selectedCategories: selectedCategories,
            pickerSelectedMonth: showMonthSelector ? pickerSelectedMonth : nil, viewingAttachmentID: attachmentToView?.id
        )
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.expenseOrIncome(snapshot), for: timestamp)
        }
    }
    
    var body: some View {
        Form {
            detailsSection

            if showMonthSelector {
                monthSection
            }

            optionsSection

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationDestination(isPresented: $showingCategoryPicker) {
            CategoryPickerView(selectedCategories: $selectedCategories, item: item, month: budgetSelectedMonth ?? Calendar.current.component(.month, from: Date()), year: budgetSelectedYear ?? Calendar.current.component(.year, from: Date()))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ItemTypePickerToolbarItem(itemType: $itemType, types: [.expense, .income])

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: saveItem) {
                    Label("Add", systemImage: "plus")
                }
                .tint(.primary)
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                AttachmentMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker) {
                    dismissKeyboard()
                }
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                focusedField = .name

                if initialDraft.wrappedValue != nil {
                    initialDraft.wrappedValue = nil
                } else {
                    // A fresh (non-restored) open — clear any draft abandoned by a previous
                    // attempt so it's never mistakenly picked up by an unrelated new one.
                    NavigationStateManager.shared.clearDraft()
                }
            }
            if showMonthSelector {
                updateDateForMonth()
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .navigationDestination(item: $attachmentToView) { attachment in
            AttachmentViewerSheet(attachment: attachment)
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
            dismissKeyboard()
        }
    }

    private var detailsSection: some View {
        Section {
            HStack {
                Text("Title")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $name, placeholder: "Income") {
                    // Advance to amount field without dismissing keyboard
                    isAmountFocused = true
                }
                .multilineTextAlignment(.trailing)
                .dismissKeyboardOnReturn(false)
                .focused($focusedField, equals: .name)
                .textInputAutocapitalization(.words)
                .onChange(of: focusedField) { oldValue, newValue in
                    if oldValue == .name && newValue != .name {
                        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .name
            }
            
            HStack {
                Text("Amount")
                Spacer()
                CalculatorStyleCurrencyTextField(
                    amount: $amount,
                    isFocused: $isAmountFocused
                ) {
                    // Dismiss keyboard on return
                    isAmountFocused = false
                }
                .frame(width: 125)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isAmountFocused = true
            }

            if itemType == .expense && isMonthlyPaymentPlan {
                PaymentAmountRow(amount: calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? 0, currencyCode: selectedCurrency.code)
            }

            CategoryPickerButton(selectedCategories: selectedCategories) {
                dismissKeyboard()
                showingCategoryPicker = true
            }

            if itemType == .income, item.isTaxSavingsEnabled {
                Toggle("Taxable", isOn: $isTaxable)
            }
        } header: {
            Text(itemType == .income ? "Income Details" : "Expense Details")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }

    private var monthSection: some View {
        Section {
            Picker("Select Month", selection: $pickerSelectedMonth) {
                ForEach(availableMonths, id: \.self) { month in
                    Text(monthDisplayName(month)).tag(month)
                }
            }
            .pickerStyle(.wheel)
            .onChange(of: pickerSelectedMonth) { _, _ in
                updateDateForMonth()
            }

            // Only editable for recurring items
            if isRecurring {
                HStack {
                    Text("Start Date")
                    Spacer()
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: date) { _, newValue in
                            pickerSelectedMonth = newValue.month
                            // If end date is before new start date, update it to match
                            if showEndDate && endDate < newValue {
                                endDate = newValue
                            }
                        }
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                Toggle("End Date", isOn: $showEndDate)

                if showEndDate {
                    HStack {
                        Text("End Date")
                        Spacer()
                        DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                            .labelsHidden()
                        DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var availableMonths: [Int] {
        let now = Date()
        // If the selected date is in the current year, only show months up to the current month
        if date.year >= now.year {
            return Array(1...now.month)
        } else {
            // For past years, show all months
            return Array(1...12)
        }
    }
    
    private var optionsSection: some View {
        Section {
            if !showMonthSelector {
                // Date picker - always enabled, label changes based on recurring state
                HStack {
                    Text(isRecurring ? "Start Date" : "Date")
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: date) { _, newValue in
                        if showEndDate && endDate < newValue { endDate = newValue }
                    }
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }

            if showRecurringOption {
                RecurringPickerRows(rule: $recurrenceRule, isRecurring: $isRecurring, startDate: date)
                    .onChange(of: recurrenceRule) { _, newRule in
                        recurringFrequency = newRule.closestLegacyFrequency
                    }
                    .onChange(of: isRecurring) { _, newValue in
                        if newValue {
                            showDate = true
                        } else {
                            showEndDate = false
                        }
                    }
            }

            if !showMonthSelector && isRecurring {
                Toggle("End Date", isOn: $showEndDate)
                    .onChange(of: showEndDate) { _, _ in
                        dismissKeyboard()
                    }

                if showEndDate {
                    HStack {
                        Text("End Date")
                        Spacer()
                        DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                            .labelsHidden()
                        DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }

        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        // Force UIKit text fields to resign first responder
        resignKeyboard()
    }

    private func saveItem() {
        switch itemType {
        case .income: addIncome()
        case .expense: addExpenseFromForm()
        case .reallocation: break
        }
    }

    private func addIncome() {
        let finalDate = showMonthSelector ? mergeEditedTime(from: Date(), intoDay: date) : date
        let newIncome = Income(
            name: defaultName(name, fallback: "Income"),
            amount: amount.roundedMoney(),
            date: finalDate,
            showDate: showDate,
            endDate: showEndDate ? endDate : nil,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments,
            isTaxable: isTaxable,
            taxPercentageOverride: nil,
            categories: selectedCategories.sorted()
        )
        incomes.insert(newIncome, forSortOrder: sortOrder)
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        dismiss()
    }

    private func addExpenseFromForm() {
        let finalAmount: Decimal
        let finalTotalAmount: Decimal?
        if isMonthlyPaymentPlan {
            finalAmount = calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? totalAmount.roundedMoney()
            finalTotalAmount = totalAmount.roundedMoney()
        } else {
            finalAmount = amount.roundedMoney()
            finalTotalAmount = nil
        }
        let finalShowDate = !isRecurring || showDate
        let newExpense = Expense(
            name: defaultName(name, fallback: "Expense"),
            amount: finalAmount,
            date: date,
            showDate: finalShowDate,
            endDate: (isMonthlyPaymentPlan || showEndDate) ? endDate : nil,
            showEndDate: isMonthlyPaymentPlan || showEndDate,
            isRecurring: isMonthlyPaymentPlan || isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: isMonthlyPaymentPlan ? nil : recurrenceRule,
            isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: finalTotalAmount,
            attachments: attachments,
            categories: selectedCategories.sorted()
        )
        expenses.insert(newExpense, forSortOrder: sortOrder)
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        dismiss()
    }

    private func updateDateForMonth() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .day], from: date)
        components.month = pickerSelectedMonth
        if let newDate = calendar.date(from: components) {
            date = newDate
        }
    }
    
}

// MARK: - Edit Expense View

struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var expense: Expense
    @Binding var expenses: [Expense]
    @Binding var incomes: [Income]
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual

    @State private var name: String
    @State private var amount: Decimal
    @State private var date: Date
    @State private var showDate: Bool
    @State private var endDate: Date
    @State private var showEndDate: Bool
    @State private var isRecurring: Bool
    @State private var recurringFrequency: RecurringFrequency
    @State private var recurrenceRule: RecurrenceRule

    // Payment plan properties
    @State private var isMonthlyPaymentPlan: Bool
    @State private var totalAmount: Decimal
    @State private var numberOfPayments: Int

    // Attachment properties
    @State private var attachments: [Attachment]
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Occurrence date for recurring edit scope
    var occurrenceDate: Date?
    var item: Item?
    // Set by the presenter when restoring a saved in-progress edit (including its nested
    // attachment viewer, if one was open), so this instance reopens with whatever the user
    // had changed rather than the saved expense's original values. Consumed and cleared on
    // first appear.
    var initialDraft: Binding<TransactionFormDraft?> = .constant(nil)
    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    // Track original recurring state
    @State private var originalIsRecurring: Bool
    @State private var originalIsMonthlyPaymentPlan: Bool

    // Track original values for change detection
    @State private var originalName: String
    @State private var originalAmount: Decimal
    @State private var originalDate: Date
    @State private var originalShowDate: Bool
    @State private var originalEndDate: Date?
    @State private var originalShowEndDate: Bool
    @State private var originalRecurringFrequency: RecurringFrequency
    @State private var originalRecurrenceRule: RecurrenceRule
    @State private var originalTotalAmount: Decimal
    @State private var originalNumberOfPayments: Int
    @State private var originalAttachments: [Attachment]

    // Category properties
    @State private var selectedCategories: Set<String>
    @State private var originalCategories: Set<String>
    @State private var showingCategoryPicker = false

    @State private var showingRecurringScopeAlert = false
    @State private var pendingRecurringScope: RecurringScope?
    @State private var showingDeleteConfirmation = false
    @State private var pendingConversion: Income? = nil
    @State private var convertedIsTaxable: Bool = true

    enum Field: Hashable {
        case name
        case amount
        case totalAmount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isTotalAmountFocused: Bool

    init(expense: Binding<Expense>, expenses: Binding<[Expense]>, incomes: Binding<[Income]> = .constant([]), occurrenceDate: Date? = nil, item: Item? = nil, initialDraft: Binding<TransactionFormDraft?> = .constant(nil)) {
        self._expense = expense
        self._expenses = expenses
        self._incomes = incomes
        self.occurrenceDate = occurrenceDate
        self.item = item
        self.initialDraft = initialDraft

        // Original values are always anchored to the true model, regardless of a restored
        // draft, since change detection must compare against what's actually saved.
        let currentExpense = expense.wrappedValue
        var initialExpenseRule = currentExpense.resolvedRule
        if initialExpenseRule.unit == .month, initialExpenseRule.monthDays.isEmpty {
            initialExpenseRule.monthDays = currentExpense.date.isLastDayOfMonth
                ? [32]
                : [Calendar.current.component(.day, from: currentExpense.date)]
        }
        let calendar = Calendar.current
        var calculatedPayments = 12
        if currentExpense.isMonthlyPaymentPlan, let end = currentExpense.endDate {
            let components = calendar.dateComponents([.month], from: currentExpense.date, to: end)
            if let months = components.month, months >= 0 {
                calculatedPayments = months + 1
            }
        }

        if let draft = initialDraft.wrappedValue {
            // Restoring an in-progress edit — seed the staged (editable) fields from it.
            self._name = State(initialValue: draft.name)
            self._amount = State(initialValue: draft.amount)
            self._date = State(initialValue: draft.date)
            self._showDate = State(initialValue: draft.showDate)
            self._endDate = State(initialValue: draft.endDate)
            self._showEndDate = State(initialValue: draft.showEndDate)
            self._isRecurring = State(initialValue: draft.isRecurring)
            self._recurringFrequency = State(initialValue: draft.recurringFrequency)
            self._recurrenceRule = State(initialValue: draft.recurrenceRule)
            self._isMonthlyPaymentPlan = State(initialValue: draft.isMonthlyPaymentPlan)
            self._totalAmount = State(initialValue: draft.totalAmount)
            self._numberOfPayments = State(initialValue: draft.numberOfPayments)
            self._attachments = State(initialValue: draft.attachments)
            self._selectedCategories = State(initialValue: draft.selectedCategories)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            // Fresh open — initialize state with current expense values to prevent flickering.
            self._name = State(initialValue: currentExpense.name)
            self._amount = State(initialValue: currentExpense.amount)
            self._date = State(initialValue: currentExpense.date)
            self._showDate = State(initialValue: currentExpense.showDate)
            self._endDate = State(initialValue: currentExpense.endDate ?? Date())
            self._showEndDate = State(initialValue: currentExpense.showEndDate)
            self._isRecurring = State(initialValue: currentExpense.isRecurring)
            self._recurringFrequency = State(initialValue: currentExpense.recurringFrequency)
            self._recurrenceRule = State(initialValue: initialExpenseRule)
            self._isMonthlyPaymentPlan = State(initialValue: currentExpense.isMonthlyPaymentPlan)
            self._totalAmount = State(initialValue: currentExpense.totalAmount ?? 0)
            self._numberOfPayments = State(initialValue: calculatedPayments)
            self._attachments = State(initialValue: currentExpense.attachments)
            self._selectedCategories = State(initialValue: Set(currentExpense.categories))
        }

        // Store original values
        self._originalIsRecurring = State(initialValue: currentExpense.isRecurring)
        self._originalIsMonthlyPaymentPlan = State(initialValue: currentExpense.isMonthlyPaymentPlan)
        self._originalName = State(initialValue: currentExpense.name)
        self._originalAmount = State(initialValue: currentExpense.amount)
        self._originalDate = State(initialValue: currentExpense.date)
        self._originalShowDate = State(initialValue: currentExpense.showDate)
        self._originalEndDate = State(initialValue: currentExpense.endDate)
        self._originalShowEndDate = State(initialValue: currentExpense.showEndDate)
        self._originalRecurringFrequency = State(initialValue: currentExpense.recurringFrequency)
        self._originalRecurrenceRule = State(initialValue: initialExpenseRule)
        self._originalTotalAmount = State(initialValue: currentExpense.totalAmount ?? 0)
        self._originalNumberOfPayments = State(initialValue: calculatedPayments)
        self._originalAttachments = State(initialValue: currentExpense.attachments)
        self._originalCategories = State(initialValue: Set(currentExpense.categories))
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress edit survives the app being terminated.
    private var draftSnapshot: TransactionFormDraft {
        TransactionFormDraft(
            name: name, amount: amount, date: date, showDate: showDate, endDate: endDate,
            showEndDate: showEndDate, isRecurring: isRecurring, recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule, isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: totalAmount, numberOfPayments: numberOfPayments, isTaxable: true,
            itemType: .expense, attachments: attachments, selectedCategories: selectedCategories,
            pickerSelectedMonth: nil, viewingAttachmentID: attachmentToView?.id
        )
    }

    private func scheduleDraftSave() {
        guard let item else { return }
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.expenseOrIncome(snapshot), for: timestamp)
        }
    }

    var body: some View {
        Form {
            detailsSection
            optionsSection

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)

            occurrenceSection
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationDestination(isPresented: $showingCategoryPicker) {
            if let item {
                CategoryPickerView(selectedCategories: $selectedCategories, item: item, month: Calendar.current.component(.month, from: occurrenceDate ?? Date()), year: Calendar.current.component(.year, from: occurrenceDate ?? Date()))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if pendingConversion != nil {
                    Menu {
                        Button { pendingConversion = nil; isMonthlyPaymentPlan = originalIsMonthlyPaymentPlan } label: {
                            Label("Expense", systemImage: "cart")
                        }
                    } label: {
                        Label("Income", systemImage: "dollarsign.circle")
                            .labelStyle(.titleOnly)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .tint(.primary)
                } else {
                    Menu {
                        Button { convertToIncome() } label: {
                            Label("Income", systemImage: "dollarsign.circle")
                        }
                    } label: {
                        Label("Expense", systemImage: "cart")
                            .labelStyle(.titleOnly)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .tint(.primary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: checkAndSaveExpense) {
                    Label("Save", systemImage: "checkmark")
                }
                .tint(.primary)
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                Spacer()
                AttachmentMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker) {
                    dismissKeyboard()
                }
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
            } else if item != nil {
                // A fresh (non-restored) open — clear any draft abandoned by a previous
                // attempt so it's never mistakenly picked up by an unrelated new one.
                NavigationStateManager.shared.clearDraft()
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
            dismissKeyboard()
        }
        .recurringEditAlert(
            isPresented: $showingRecurringScopeAlert,
            pendingScope: $pendingRecurringScope,
            applyEdit: applyExpenseEdit
        )
        .background {
            AlertContainer {
                Color.clear
                    .alert((originalIsRecurring || originalIsMonthlyPaymentPlan) ? "Delete Expense?" : "Move to Trash?", isPresented: $showingDeleteConfirmation) {
                        if originalIsRecurring || originalIsMonthlyPaymentPlan {
                            Button("Trash All Occurrences", role: .destructive) { performDeleteExpense(scope: .all) }
                            Button("Delete Current and Future", role: .destructive) { performDeleteExpense(scope: .currentAndFuture) }
                            Button("Delete Current Occurrence", role: .destructive) { performDeleteExpense(scope: .currentOnly) }
                        } else {
                            Button("Confirm", role: .destructive) { performDeleteExpense(scope: nil) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if originalIsRecurring || originalIsMonthlyPaymentPlan {
                            Text("This is a recurring item. Choose which occurrences to delete:")
                        } else {
                            Text("'\(expense.name)' will be moved to Trash and permanently deleted after 30 days.")
                        }
                    }

            }
        }
    }

    private func convertToIncome() {
        isMonthlyPaymentPlan = false
        pendingConversion = Income(
            id: expense.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Income" : name,
            amount: amount.roundedMoney(),
            date: date,
            showDate: showDate,
            endDate: showEndDate ? endDate : nil,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments,
            isTaxable: true,
            taxPercentageOverride: nil,
            createdAt: expense.createdAt,
            categories: selectedCategories.sorted()
        )
    }

    private var detailsSection: some View {
        Section {
            titleField
            amountField

            if pendingConversion == nil && isMonthlyPaymentPlan {
                paymentAmountField
            }

            CategoryPickerButton(selectedCategories: selectedCategories) {
                dismissKeyboard()
                guard item != nil else { return }
                showingCategoryPicker = true
            }

            if pendingConversion != nil, item?.isTaxSavingsEnabled == true {
                Toggle("Taxable", isOn: $convertedIsTaxable)
            }

            if pendingConversion == nil {
                Toggle("Payment Plan", isOn: $isMonthlyPaymentPlan)
            }
        } header: {
            Text(pendingConversion == nil ? "Expense Details" : "Income Details")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private var occurrenceSection: some View {
        if originalIsRecurring || originalIsMonthlyPaymentPlan {
            let occ = occurrenceDate ?? date
            Section {
                HStack {
                    if originalIsMonthlyPaymentPlan, let payNum = paymentNumber(for: occ) {
                        Text("Payment \(payNum) of \(numberOfPayments)")
                    } else {
                        Text("Item Date")
                    }
                    Spacer()
                    Text(occ, format: dateFormat.style)
                }
            }
        }
    }

    private func paymentNumber(for occ: Date) -> Int? {
        guard originalIsMonthlyPaymentPlan else { return nil }
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: originalDate)
        let startMonth = calendar.component(.month, from: originalDate)
        let occYear = calendar.component(.year, from: occ)
        let occMonth = calendar.component(.month, from: occ)
        let months = (occYear - startYear) * 12 + (occMonth - startMonth)
        guard months >= 0 else { return nil }
        return months + 1
    }

    private var titleField: some View {
        HStack {
            Text("Title")
            Spacer()
            CursorAtEndTextField_SwiftUI(text: $name, placeholder: "Expense") {
                // Advance to next field without dismissing keyboard
                if isMonthlyPaymentPlan {
                    isTotalAmountFocused = true
                } else {
                    isAmountFocused = true
                }
            }
            .multilineTextAlignment(.trailing)
            .dismissKeyboardOnReturn(false)
            .textInputAutocapitalization(.words)
            .focused($focusedField, equals: .name)
            .onChange(of: focusedField) { oldValue, newValue in
                if oldValue == .name && newValue != .name {
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .name
        }
    }
    
    private var amountField: some View {
        HStack {
            Text(isMonthlyPaymentPlan ? "Total" : "Amount")
            Spacer()
            CalculatorStyleCurrencyTextField(
                amount: isMonthlyPaymentPlan ? $totalAmount : $amount,
                isFocused: isMonthlyPaymentPlan ? $isTotalAmountFocused : $isAmountFocused
            ) {
                // Dismiss keyboard on return
                isAmountFocused = false
                isTotalAmountFocused = false
            }
            .frame(width: 125)
            .lineLimit(1)
            .onChange(of: totalAmount) { _, _ in
                if isMonthlyPaymentPlan {
                    endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isMonthlyPaymentPlan {
                isTotalAmountFocused = true
            } else {
                isAmountFocused = true
            }
        }
        .id("mainAmountField") // Stable identity
    }
    
    // New field to show calculated payment amount (read-only)
    private var paymentAmountField: some View {
        PaymentAmountRow(amount: calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? 0, currencyCode: selectedCurrency.code)
    }

    private var optionsSection: some View {
        Section {
            startDatePicker
            frequencyPicker
            NumberOfPaymentsPicker(
                numberOfPayments: $numberOfPayments,
                endDate: $endDate,
                date: date,
                recurringFrequency: recurringFrequency,
                isEnabled: isMonthlyPaymentPlan
            )
            endDateToggle
            endDatePicker
        }
    }
    
    private var frequencyPicker: some View {
        RecurringPickerRows(
            rule: $recurrenceRule,
            isRecurring: $isRecurring,
            startDate: date,
            paymentPlan: pendingConversion != nil ? nil : PaymentPlanBindings(
                isEnabled: $isMonthlyPaymentPlan,
                numberOfPayments: $numberOfPayments,
                amount: $amount,
                endDate: $endDate,
                totalAmount: totalAmount,
                recurringFrequency: recurringFrequency,
                currencyCode: selectedCurrency.code
            )
        )
        .onChange(of: recurrenceRule) { _, newRule in
            recurringFrequency = newRule.closestLegacyFrequency
            if isMonthlyPaymentPlan {
                endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
            }
        }
        .onChange(of: isRecurring) { _, newValue in
            if newValue && !isMonthlyPaymentPlan {
                showDate = true
            } else if !isMonthlyPaymentPlan {
                showDate = false
                showEndDate = false
            }
        }
        .onChange(of: isMonthlyPaymentPlan) { _, newValue in
            if newValue {
                isRecurring = true
                showDate = true
                showEndDate = true
                if totalAmount.isEffectivelyZero && amount.isEffectivelyPositive {
                    totalAmount = amount
                }
                endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
            } else {
                isRecurring = false
                showDate = false
                showEndDate = false
            }
        }
    }
    
    private var startDatePicker: some View {
        Group {
            // Edit views should not restrict date range - only Add views restrict dates when called from month sheets
            HStack {
                Text(isRecurring || isMonthlyPaymentPlan ? "Start Date" : "Date")
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: date) { _, newValue in
                        if showEndDate && !isMonthlyPaymentPlan && endDate < newValue {
                            endDate = newValue
                        }
                        if isMonthlyPaymentPlan {
                            endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
                        }
                    }
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }
    
    @ViewBuilder
    private var endDatePicker: some View {
        // Edit views should not restrict date range - only Add views restrict dates when called from month sheets
        if showEndDate && isRecurring {
            HStack {
                Text("End Date")
                Spacer()
                DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                    .labelsHidden()
                    .disabled(isMonthlyPaymentPlan)
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(isMonthlyPaymentPlan)
            }
        }
    }

    @ViewBuilder
    private var endDateToggle: some View {
        if isRecurring && !isMonthlyPaymentPlan {
            Toggle("End Date", isOn: $showEndDate)
        }
    }
    
    private func dismissKeyboard() {
        focusedField = nil
        resignKeyboard()
    }

    /// Checks if changes were made and determines edit scope for recurring items
    /// Shows alert for multi-occurrence recurring items, bypasses alert for single occurrences
    /// Payment plan items always edit all occurrences without showing the scope alert
    private func checkAndSaveExpense() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        if pendingConversion != nil { saveExpense(); return }
        // Check if the original item was recurring or a payment plan
        if originalIsRecurring || originalIsMonthlyPaymentPlan {
            // Check if anything actually changed
            let hasChanges = hasExpenseChanges()
            
            if hasChanges {
                // Payment plan items always edit all occurrences - skip the scope alert
                if originalIsMonthlyPaymentPlan {
                    saveExpense()
                    dismiss()
                    return
                }
                
                // Check if ONLY the end date changed (and nothing else)
                let onlyEndDateChanged = hasOnlyEndDateChanged()
                
                if onlyEndDateChanged {
                    // Only end date changed - apply to all occurrences without showing alert
                    saveExpense()
                    dismiss()
                } else if hasOnlyCategoryChanged() {
                    // Only category changed - apply to all occurrences without showing alert
                    saveExpense()
                    dismiss()
                } else if hasOnlyOneOccurrence(startDate: originalDate, endDate: originalEndDate, frequencyRawValue: originalRecurringFrequency.rawValue, rule: originalRecurrenceRule) {
                    saveExpense()
                    dismiss()
                } else {
                    showingRecurringScopeAlert = true
                }
            } else {
                print("⏭️ EditExpenseView: No changes detected, skipping save")
                dismiss()
            }
        } else {
            if hasExpenseChanges() {
                saveExpense()
            } else {
                print("⏭️ EditExpenseView: No changes detected, skipping save")
            }
            dismiss()
        }
    }

    private func hasOnlyEndDateChanged() -> Bool {
        // Check if end date actually changed
        let currentEndDate = (isMonthlyPaymentPlan || showEndDate) ? endDate : nil
        let endDateChanged = currentEndDate != originalEndDate
        
        // If end date didn't change, return false
        guard endDateChanged else { return false }
        
        // Verify no other fields changed
        if name != originalName { return false }
        if !amount.isEffectivelyEqual(to: originalAmount) { return false }
        if date != originalDate { return false }
        if showDate != originalShowDate { return false }
        if isRecurring != originalIsRecurring { return false }
        if isMonthlyPaymentPlan != originalIsMonthlyPaymentPlan { return false }
        if recurringFrequency != originalRecurringFrequency { return false }
        if recurrenceRule != originalRecurrenceRule { return false }
        if !totalAmount.isEffectivelyEqual(to: originalTotalAmount) { return false }
        if numberOfPayments != originalNumberOfPayments { return false }

        // showEndDate toggle state change is acceptable when only end date changes
        return attachmentsSameByID(attachments, originalAttachments)
    }

    private func hasOnlyCategoryChanged() -> Bool {
        guard selectedCategories != originalCategories else { return false }
        if name != originalName { return false }
        if !amount.isEffectivelyEqual(to: originalAmount) { return false }
        if date != originalDate { return false }
        if showDate != originalShowDate { return false }
        if showEndDate != originalShowEndDate { return false }
        if isRecurring != originalIsRecurring { return false }
        if isMonthlyPaymentPlan != originalIsMonthlyPaymentPlan { return false }
        if recurringFrequency != originalRecurringFrequency { return false }
        if recurrenceRule != originalRecurrenceRule { return false }
        if !totalAmount.isEffectivelyEqual(to: originalTotalAmount) { return false }
        if numberOfPayments != originalNumberOfPayments { return false }
        let currentEndDate = (isMonthlyPaymentPlan || showEndDate) ? endDate : nil
        if currentEndDate != originalEndDate { return false }
        return attachmentsSameByID(attachments, originalAttachments)
    }

    /// Checks if any editable fields have changed from their original values
    private func hasExpenseChanges() -> Bool {
        if name != originalName { return true }
        if !amount.isEffectivelyEqual(to: originalAmount) { return true }
        if date != originalDate { return true }
        if showDate != originalShowDate { return true }
        if showEndDate != originalShowEndDate { return true }
        if isRecurring != originalIsRecurring { return true }
        if isMonthlyPaymentPlan != originalIsMonthlyPaymentPlan { return true }
        if recurringFrequency != originalRecurringFrequency { return true }
        if recurrenceRule != originalRecurrenceRule { return true }
        if !totalAmount.isEffectivelyEqual(to: originalTotalAmount) { return true }
        if numberOfPayments != originalNumberOfPayments { return true }
        if selectedCategories != originalCategories { return true }
        let currentEndDate = (isMonthlyPaymentPlan || showEndDate) ? endDate : nil
        if currentEndDate != originalEndDate { return true }
        return !attachmentsSameByID(attachments, originalAttachments)
    }

    private func applyExpenseEdit() {
        guard let scope = pendingRecurringScope else { saveExpense(); return }
        let shouldFallback = applyRecurringItemEdit(
            scope: scope, items: &expenses, itemID: expense.id,
            occurrenceDate: occurrenceDate, itemDate: expense.date, editedDate: date,
            createEdited: createEditedExpense,
            onOneTimeCreated: { $0.isMonthlyPaymentPlan = false }
        )
        if shouldFallback {
            saveExpense()
        } else {
            pendingRecurringScope = nil
            let temp = expenses; expenses = temp
            dismiss()
        }
    }
    
    private func computePaymentAmounts() -> (amount: Decimal, totalAmount: Decimal?) {
        isMonthlyPaymentPlan
            ? (calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? totalAmount.roundedMoney(), totalAmount.roundedMoney())
            : (amount.roundedMoney(), nil)
    }

    /// Creates a new Expense object with current edited values
    private func createEditedExpense() -> Expense {
        let (finalAmount, finalTotalAmount) = computePaymentAmounts()
        return Expense(
            name: name,
            amount: finalAmount,
            date: date,
            showDate: showDate,
            endDate: (isMonthlyPaymentPlan || showEndDate) ? endDate : nil,
            showEndDate: isMonthlyPaymentPlan || showEndDate,
            isRecurring: isMonthlyPaymentPlan || isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: isMonthlyPaymentPlan ? nil : recurrenceRule,
            isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: finalTotalAmount,
            attachments: attachments,
            categories: selectedCategories.sorted()
        )
    }

    /// Updates the existing expense binding with edited values
    /// Replaces the expense in the array to trigger onChange for persistence
    private func saveExpense() {
        if pendingConversion != nil {
            let finalIncome = Income(
                id: expense.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Income" : name,
                amount: amount.roundedMoney(),
                date: date,
                showDate: showDate,
                endDate: showEndDate ? endDate : nil,
                showEndDate: showEndDate,
                isRecurring: isRecurring,
                recurringFrequency: recurringFrequency,
                recurrenceRule: recurrenceRule,
                attachments: attachments,
                isTaxable: convertedIsTaxable,
                taxPercentageOverride: nil,
                createdAt: expense.createdAt,
                categories: selectedCategories.sorted()
            )
            incomes.insert(finalIncome, forSortOrder: sortOrder)
            expenses.removeAll { $0.id == expense.id }
            pendingConversion = nil
            dismiss()
            return
        }
        let (finalAmount, finalTotalAmount) = computePaymentAmounts()

        // Update the expense binding - this will trigger the onChange handler in the parent view
        expense.name = name
        expense.amount = finalAmount
        expense.date = date
        expense.showDate = showDate
        expense.endDate = (isMonthlyPaymentPlan || showEndDate) ? endDate : nil
        expense.showEndDate = isMonthlyPaymentPlan || showEndDate
        expense.isRecurring = isMonthlyPaymentPlan || isRecurring
        expense.recurringFrequency = recurringFrequency
        expense.recurrenceRule = isMonthlyPaymentPlan ? nil : recurrenceRule
        expense.isMonthlyPaymentPlan = isMonthlyPaymentPlan
        expense.totalAmount = finalTotalAmount
        expense.attachments = attachments
        expense.categories = selectedCategories.sorted()

        // Force array modification to trigger onChange by replacing the expense in the array
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
            print("✅ EditExpenseView: Changes saved for expense '\(name)'")
        }

        dismiss()
    }

    private func performDeleteExpense(scope: RecurringScope?) {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        pendingConversion = nil
        let now = Date()
        if let scope = scope {
            if scope == .all {
                for i in expenses.indices where expenses[i].id == expense.id {
                    expenses[i].deletedDate = now
                }
            } else {
                var pendingScope: RecurringScope? = scope
                var adjustedExpense = expense
                if let occ = occurrenceDate {
                    adjustedExpense.date = occ
                }
                applyRecurringItemDeletion(item: adjustedExpense, items: &expenses, pendingScope: &pendingScope)
            }
        } else {
            if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
                expenses[idx].deletedDate = now
            }
        }
        dismiss()
    }
    
}

// MARK: - Edit Income View (for Budget Page)

struct EditIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var income: Income
    @Binding var incomes: [Income]
    @Binding var expenses: [Expense]
    var item: Item
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual

    @State private var name: String
    @State private var amount: Decimal
    @State private var date: Date
    @State private var showDate: Bool
    @State private var endDate: Date
    @State private var showEndDate: Bool
    @State private var isRecurring: Bool
    @State private var recurringFrequency: RecurringFrequency
    @State private var recurrenceRule: RecurrenceRule
    @State private var attachments: [Attachment]
    @State private var attachmentToView: Attachment?
    @State private var isTaxable: Bool
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Occurrence date for recurring edit scope
    var occurrenceDate: Date?
    // Set by the presenter when restoring a saved in-progress edit (including its nested
    // attachment viewer, if one was open), so this instance reopens with whatever the user
    // had changed rather than the saved income's original values. Consumed and cleared on
    // first appear.
    var initialDraft: Binding<TransactionFormDraft?> = .constant(nil)
    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    // Track original recurring state
    @State private var originalIsRecurring: Bool

    // Track original values for change detection
    @State private var originalName: String
    @State private var originalAmount: Decimal
    @State private var originalDate: Date
    @State private var originalShowDate: Bool
    @State private var originalEndDate: Date?
    @State private var originalShowEndDate: Bool
    @State private var originalRecurringFrequency: RecurringFrequency
    @State private var originalRecurrenceRule: RecurrenceRule
    @State private var originalIsTaxable: Bool
    @State private var originalAttachments: [Attachment]

    // Category properties
    @State private var selectedCategories: Set<String>
    @State private var originalCategories: Set<String>
    @State private var showingCategoryPicker = false

    @State private var showingRecurringScopeAlert = false
    @State private var pendingRecurringScope: RecurringScope?
    @State private var showingDeleteConfirmation = false
    @State private var pendingConversion: Expense? = nil

    enum Field: Hashable {
        case name
        case amount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool

    init(income: Binding<Income>, incomes: Binding<[Income]>, expenses: Binding<[Expense]> = .constant([]), item: Item, occurrenceDate: Date? = nil, initialDraft: Binding<TransactionFormDraft?> = .constant(nil)) {
        self._income = income
        self._incomes = incomes
        self._expenses = expenses
        self.item = item
        self.occurrenceDate = occurrenceDate
        self.initialDraft = initialDraft

        // Original values are always anchored to the true model, regardless of a restored
        // draft, since change detection must compare against what's actually saved.
        let currentIncome = income.wrappedValue
        var initialIncomeRule = currentIncome.resolvedRule
        if initialIncomeRule.unit == .month, initialIncomeRule.monthDays.isEmpty {
            initialIncomeRule.monthDays = currentIncome.date.isLastDayOfMonth
                ? [32]
                : [Calendar.current.component(.day, from: currentIncome.date)]
        }

        if let draft = initialDraft.wrappedValue {
            // Restoring an in-progress edit — seed the staged (editable) fields from it.
            self._name = State(initialValue: draft.name)
            self._amount = State(initialValue: draft.amount)
            self._date = State(initialValue: draft.date)
            self._showDate = State(initialValue: draft.showDate)
            self._endDate = State(initialValue: draft.endDate)
            self._showEndDate = State(initialValue: draft.showEndDate)
            self._isRecurring = State(initialValue: draft.isRecurring)
            self._recurringFrequency = State(initialValue: draft.recurringFrequency)
            self._recurrenceRule = State(initialValue: draft.recurrenceRule)
            self._attachments = State(initialValue: draft.attachments)
            self._isTaxable = State(initialValue: draft.isTaxable)
            self._selectedCategories = State(initialValue: draft.selectedCategories)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            // Fresh open — initialize state with current income values to prevent flickering.
            self._name = State(initialValue: currentIncome.name)
            self._amount = State(initialValue: currentIncome.amount)
            self._date = State(initialValue: currentIncome.date)
            self._showDate = State(initialValue: currentIncome.showDate)
            self._endDate = State(initialValue: currentIncome.endDate ?? Date())
            self._showEndDate = State(initialValue: currentIncome.showEndDate)
            self._isRecurring = State(initialValue: currentIncome.isRecurring)
            self._recurringFrequency = State(initialValue: currentIncome.recurringFrequency)
            self._recurrenceRule = State(initialValue: initialIncomeRule)
            self._attachments = State(initialValue: currentIncome.attachments)
            self._isTaxable = State(initialValue: currentIncome.isTaxable)
            self._selectedCategories = State(initialValue: Set(currentIncome.categories))
        }

        // Store original values
        self._originalIsRecurring = State(initialValue: currentIncome.isRecurring)
        self._originalName = State(initialValue: currentIncome.name)
        self._originalAmount = State(initialValue: currentIncome.amount)
        self._originalDate = State(initialValue: currentIncome.date)
        self._originalShowDate = State(initialValue: currentIncome.showDate)
        self._originalEndDate = State(initialValue: currentIncome.endDate)
        self._originalShowEndDate = State(initialValue: currentIncome.showEndDate)
        self._originalRecurringFrequency = State(initialValue: currentIncome.recurringFrequency)
        self._originalRecurrenceRule = State(initialValue: initialIncomeRule)
        self._originalIsTaxable = State(initialValue: currentIncome.isTaxable)
        self._originalAttachments = State(initialValue: currentIncome.attachments)
        self._originalCategories = State(initialValue: Set(currentIncome.categories))
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress edit survives the app being terminated.
    private var draftSnapshot: TransactionFormDraft {
        TransactionFormDraft(
            name: name, amount: amount, date: date, showDate: showDate, endDate: endDate,
            showEndDate: showEndDate, isRecurring: isRecurring, recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule, isMonthlyPaymentPlan: false, totalAmount: 0,
            numberOfPayments: 12, isTaxable: isTaxable, itemType: .income, attachments: attachments,
            selectedCategories: selectedCategories, pickerSelectedMonth: nil,
            viewingAttachmentID: attachmentToView?.id
        )
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.expenseOrIncome(snapshot), for: timestamp)
        }
    }

    private var titleField: some View {
        HStack {
            Text("Title")
            Spacer()
            CursorAtEndTextField_SwiftUI(text: $name, placeholder: "Income") {
                isAmountFocused = true
            }
            .multilineTextAlignment(.trailing)
            .dismissKeyboardOnReturn(false)
            .textInputAutocapitalization(.words)
            .focused($focusedField, equals: .name)
            .onChange(of: focusedField) { oldValue, newValue in
                if oldValue == .name && newValue != .name {
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .name
        }
    }

    private var amountField: some View {
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
        .onTapGesture {
            isAmountFocused = true
        }
    }

    var body: some View {
        Form {
            Section {
                titleField
                amountField

                CategoryPickerButton(selectedCategories: selectedCategories) {
                    dismissKeyboard()
                    showingCategoryPicker = true
                }

                if item.isTaxSavingsEnabled, pendingConversion == nil {
                    Toggle("Taxable", isOn: $isTaxable)
                }
            } header: {
                Text(pendingConversion == nil ? "Income Details" : "Expense Details")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .textCase(nil)
            }

            Section {
                // Date picker - always enabled, label changes based on recurring state
                // Edit views should not restrict date range - only Add views restrict dates when called from month sheets
                HStack {
                    Text(isRecurring ? "Start Date" : "Date")
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: date) { _, newValue in
                            // If end date is before new start date, update it to match
                            if showEndDate && endDate < newValue {
                                endDate = newValue
                            }
                        }
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                RecurringPickerRows(rule: $recurrenceRule, isRecurring: $isRecurring, startDate: date)
                    .onChange(of: recurrenceRule) { _, newRule in
                        recurringFrequency = newRule.closestLegacyFrequency
                    }
                    .onChange(of: isRecurring) { _, newValue in
                        if newValue {
                            showDate = true
                        } else {
                            showEndDate = false
                        }
                    }

                if isRecurring {
                    Toggle("End Date", isOn: $showEndDate)
                }

                // End date picker
                if showEndDate && isRecurring {
                    HStack {
                        Text("End Date")
                        Spacer()
                        DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                            .labelsHidden()
                        DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)

            if originalIsRecurring {
                let occ = occurrenceDate ?? date
                Section {
                    HStack {
                        Text("Item Date")
                        Spacer()
                        Text(occ, format: dateFormat.style)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationDestination(isPresented: $showingCategoryPicker) {
            CategoryPickerView(selectedCategories: $selectedCategories, item: item, month: Calendar.current.component(.month, from: occurrenceDate ?? Date()), year: Calendar.current.component(.year, from: occurrenceDate ?? Date()))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if pendingConversion != nil {
                    Menu {
                        Button { pendingConversion = nil } label: {
                            Label("Income", systemImage: "dollarsign.circle")
                        }
                    } label: {
                        Label("Expense", systemImage: "cart")
                            .labelStyle(.titleOnly)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .tint(.primary)
                } else {
                    Menu {
                        Button { convertToExpense() } label: {
                            Label("Expense", systemImage: "cart")
                        }
                    } label: {
                        Label("Income", systemImage: "dollarsign.circle")
                            .labelStyle(.titleOnly)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .tint(.primary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: checkAndSaveIncome) {
                    Label("Save", systemImage: "checkmark")
                }
                .tint(.primary)
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                Spacer()
                AttachmentMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker) {
                    dismissKeyboard()
                }
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
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
            dismissKeyboard()
        }
        .recurringEditAlert(
            isPresented: $showingRecurringScopeAlert,
            pendingScope: $pendingRecurringScope,
            applyEdit: applyIncomeEdit
        )
        .background {
            AlertContainer {
                Color.clear
                    .alert(originalIsRecurring ? "Delete Income?" : "Move to Trash?", isPresented: $showingDeleteConfirmation) {
                        if originalIsRecurring {
                            Button("Trash All Occurrences", role: .destructive) { performDeleteIncome(scope: .all) }
                            Button("Delete Current and Future", role: .destructive) { performDeleteIncome(scope: .currentAndFuture) }
                            Button("Delete Current Occurrence", role: .destructive) { performDeleteIncome(scope: .currentOnly) }
                        } else {
                            Button("Confirm", role: .destructive) { performDeleteIncome(scope: nil) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if originalIsRecurring {
                            Text("This is a recurring item. Choose which occurrences to delete:")
                        } else {
                            Text("'\(income.name)' will be moved to Trash and permanently deleted after 30 days.")
                        }
                    }

            }
        }
    }

    private func convertToExpense() {
        pendingConversion = Expense(
            id: income.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Expense" : name,
            amount: amount.roundedMoney(),
            date: date,
            showDate: showDate,
            endDate: showEndDate ? endDate : nil,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments,
            createdAt: income.createdAt,
            categories: selectedCategories.sorted()
        )
    }

    private func dismissKeyboard() {
        focusedField = nil
        resignKeyboard()
    }

    private func checkAndSaveIncome() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        if pendingConversion != nil { saveIncome(); return }
        // Check if the original item was recurring
        if originalIsRecurring {
            // Check if anything actually changed
            let hasChanges = hasIncomeChanges()
            
            if hasChanges {
                // Check if ONLY the end date changed (and nothing else)
                let onlyEndDateChanged = hasOnlyEndDateChanged()
                
                if onlyEndDateChanged {
                    // Only end date changed - apply to all occurrences without showing alert
                    saveIncome()
                    dismiss()
                } else if hasOnlyCategoryChanged() {
                    // Only category changed - apply to all occurrences without showing alert
                    saveIncome()
                    dismiss()
                } else if hasOnlyOneOccurrence(startDate: originalDate, endDate: originalEndDate, frequencyRawValue: originalRecurringFrequency.rawValue, rule: originalRecurrenceRule) {
                    saveIncome()
                    dismiss()
                } else {
                    showingRecurringScopeAlert = true
                }
            } else {
                print("⏭️ EditIncomeView: No changes detected, skipping save")
                dismiss()
            }
        } else {
            if hasIncomeChanges() {
                saveIncome()
            } else {
                print("⏭️ EditIncomeView: No changes detected, skipping save")
            }
            dismiss()
        }
    }

    private func hasOnlyEndDateChanged() -> Bool {
        // Check if end date actually changed
        let currentEndDate = showEndDate ? endDate : nil
        let endDateChanged = currentEndDate != originalEndDate
        
        // If end date didn't change, return false
        guard endDateChanged else { return false }
        
        // Check if anything else changed
        if name != originalName { return false }
        if !amount.isEffectivelyEqual(to: originalAmount) { return false }
        if date != originalDate { return false }
        if showDate != originalShowDate { return false }
        if isRecurring != originalIsRecurring { return false }
        if recurringFrequency != originalRecurringFrequency { return false }
        if recurrenceRule != originalRecurrenceRule { return false }
        if isTaxable != originalIsTaxable { return false }

        // showEndDate might have changed to enable editing the end date, which is fine
        return attachmentsSameByID(attachments, originalAttachments)
    }

    private func hasOnlyCategoryChanged() -> Bool {
        guard selectedCategories != originalCategories else { return false }
        if name != originalName { return false }
        if !amount.isEffectivelyEqual(to: originalAmount) { return false }
        if date != originalDate { return false }
        if showDate != originalShowDate { return false }
        if showEndDate != originalShowEndDate { return false }
        if isRecurring != originalIsRecurring { return false }
        if recurringFrequency != originalRecurringFrequency { return false }
        if recurrenceRule != originalRecurrenceRule { return false }
        if isTaxable != originalIsTaxable { return false }
        let currentEndDate = showEndDate ? endDate : nil
        if currentEndDate != originalEndDate { return false }
        return attachmentsSameByID(attachments, originalAttachments)
    }

    private func hasIncomeChanges() -> Bool {
        if name != originalName { return true }
        if !amount.isEffectivelyEqual(to: originalAmount) { return true }
        if date != originalDate { return true }
        if showDate != originalShowDate { return true }
        if showEndDate != originalShowEndDate { return true }
        if isRecurring != originalIsRecurring { return true }
        if recurringFrequency != originalRecurringFrequency { return true }
        if recurrenceRule != originalRecurrenceRule { return true }
        if isTaxable != originalIsTaxable { return true }
        if selectedCategories != originalCategories { return true }
        let currentEndDate = showEndDate ? endDate : nil
        if currentEndDate != originalEndDate { return true }
        return !attachmentsSameByID(attachments, originalAttachments)
    }
    
    private func applyIncomeEdit() {
        guard let scope = pendingRecurringScope else { saveIncome(); return }
        let shouldFallback = applyRecurringItemEdit(
            scope: scope, items: &incomes, itemID: income.id,
            occurrenceDate: occurrenceDate, itemDate: income.date, editedDate: date,
            createEdited: createEditedIncome
        )
        if shouldFallback {
            saveIncome()
        } else {
            pendingRecurringScope = nil
            let temp = incomes; incomes = temp
            dismiss()
        }
    }
    
    private func createEditedIncome() -> Income {
        return Income(
            name: name,
            amount: amount.roundedMoney(),
            date: date,
            showDate: showDate,
            endDate: showEndDate ? endDate : nil,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments,
            isTaxable: isTaxable,
            taxPercentageOverride: nil,
            categories: selectedCategories.sorted()
        )
    }

    private func saveIncome() {
        if pendingConversion != nil {
            let finalExpense = Expense(
                id: income.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Expense" : name,
                amount: amount.roundedMoney(),
                date: date,
                showDate: showDate,
                endDate: showEndDate ? endDate : nil,
                showEndDate: showEndDate,
                isRecurring: isRecurring,
                recurringFrequency: recurringFrequency,
                recurrenceRule: recurrenceRule,
                attachments: attachments,
                createdAt: income.createdAt,
                categories: selectedCategories.sorted()
            )
            expenses.insert(finalExpense, forSortOrder: sortOrder)
            incomes.removeAll { $0.id == income.id }
            pendingConversion = nil
            dismiss()
            return
        }
        // Update the income binding - this will trigger the onChange handler in the parent view
        income.name = name
        income.amount = amount.roundedMoney()
        income.date = date
        income.showDate = showDate
        income.endDate = showEndDate ? endDate : nil
        income.showEndDate = showEndDate
        income.isRecurring = isRecurring
        income.recurringFrequency = recurringFrequency
        income.recurrenceRule = recurrenceRule
        income.attachments = attachments
        income.isTaxable = isTaxable
        income.taxPercentageOverride = nil
        income.categories = selectedCategories.sorted()

        // Force array modification to trigger onChange by replacing the income in the array
        if let index = incomes.firstIndex(where: { $0.id == income.id }) {
            incomes[index] = income
            print("✅ EditIncomeView: Changes saved for income '\(name)'")
        }

        dismiss()
    }

    private func performDeleteIncome(scope: RecurringScope?) {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        pendingConversion = nil
        let now = Date()
        if let scope = scope {
            if scope == .all {
                for i in incomes.indices where incomes[i].id == income.id {
                    incomes[i].deletedDate = now
                }
            } else {
                var pendingScope: RecurringScope? = scope
                var adjustedIncome = income
                if let occ = occurrenceDate {
                    adjustedIncome.date = occ
                }
                applyRecurringItemDeletion(item: adjustedIncome, items: &incomes, pendingScope: &pendingScope)
            }
        } else {
            if let idx = incomes.firstIndex(where: { $0.id == income.id }) {
                incomes[idx].deletedDate = now
            }
        }
        dismiss()
    }
    
}

