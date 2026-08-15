//
//  AddEditViews.swift
//  K Test
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Shared Date Range Utilities

/// Returns a closed date range covering every day of the specified month.
private func monthDateRange(month: Int, year: Int) -> ClosedRange<Date> {
    let calendar = Calendar.current
    guard let startDate = calendar.firstOfMonth(month: month, year: year),
          let range = calendar.range(of: .day, in: .month, for: startDate),
          let endDate = calendar.date(from: DateComponents(year: year, month: month, day: range.count)) else {
        let fallback = Date()
        return fallback...fallback
    }
    return startDate...endDate
}

/// Returns a closed date range from `startDate` (or month start if later) to the end of the specified month.
private func endDateRange(month: Int, year: Int, startDate: Date) -> ClosedRange<Date> {
    let calendar = Calendar.current
    guard let monthStartDate = calendar.firstOfMonth(month: month, year: year),
          let range = calendar.range(of: .day, in: .month, for: monthStartDate),
          let monthEndDate = calendar.date(from: DateComponents(year: year, month: month, day: range.count)) else {
        return startDate...startDate
    }
    let rangeStart = max(startDate, monthStartDate)
    if rangeStart > monthEndDate { return monthStartDate...monthEndDate }
    return rangeStart...monthEndDate
}

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
private func calculatePaymentAmount(total: Double, payments: Int) -> Double? {
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
        oneTime.isRecurring = false
        onOneTimeCreated(&oneTime)
        items.append(oneTime)
    }
    return false
}

// MARK: - Shared Date Initialization Helper

/// Computes the initial date for Add views from month/year/day context or defaults to now.
/// Priority: defaultDate > selectedMonth/Year/Day > current date
private func computeInitialDate(selectedMonth: Int?, selectedYear: Int?, selectedDay: Int?, defaultDate: Date?) -> Date {
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
    let amount: Binding<Double>
    let endDate: Binding<Date>
    let totalAmount: Double
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
        Picker("Frequency", selection: frequencyBinding) {
            Text("Daily").tag(FrequencyOption.recurring(.day))
            Text("Weekly").tag(FrequencyOption.recurring(.week))
            Text("Monthly").tag(FrequencyOption.recurring(.month))
            Text("Yearly").tag(FrequencyOption.recurring(.year))
            Divider()
            Text("One Time").tag(FrequencyOption.oneTime)
        }
        .pickerStyle(.menu)

        Stepper(value: $rule.interval, in: 1...99) {
            if isRecurring {
                Text(intervalLabel)
            } else {
                Text("Every Time")
            }
        }
        .disabled(!isRecurring)
        .blur(radius: isRecurring ? 0 : 5)

        RecurringExtraSections(rule: $rule, isRecurring: isRecurring, startDate: startDate)

        if let pp = paymentPlan {
            Toggle("Payment Plan", isOn: pp.isEnabled)
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

/// Weekday selector for Weekly frequency. Rendered inside the main options Section.
struct RecurringExtraSections: View {
    @Binding var rule: RecurrenceRule
    let isRecurring: Bool
    let startDate: Date

    var body: some View {
        let isWeekly = isRecurring && rule.unit == .week
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 0) {
            ForEach(1...7, id: \.self) { wd in
                let selected = isWeekly && rule.weekdays.contains(wd)
                Button {
                    if rule.weekdays.contains(wd) {
                        if rule.weekdays.count > 1 { rule.weekdays.remove(wd) }
                    } else {
                        rule.weekdays.insert(wd)
                    }
                } label: {
                    Text(symbols[wd - 1])
                        .font(.callout.bold())
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
        .blur(radius: isWeekly ? 0 : 5)
        .disabled(!isWeekly)
    }
}

// MARK: - Payment Amount Row

/// Read-only row showing the calculated per-payment amount for a payment plan.
struct PaymentAmountRow: View {
    let amount: Double
    let currencyCode: String

    var body: some View {
        HStack {
            Text("Payment Amount")
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
    let totalAmount: Double
    let date: Date
    let recurringFrequency: RecurringFrequency
    var isEnabled: Bool = true

    var body: some View {
        Stepper(value: $numberOfPayments, in: 2...999) {
            Text("\(numberOfPayments) Payments")
        }
        .disabled(!isEnabled)
        .blur(radius: isEnabled ? 0 : 5)
        .onChange(of: numberOfPayments) { _, _ in
            endDate = calculateEndDate(from: date, frequency: recurringFrequency, payments: numberOfPayments)
        }
    }
}

// MARK: - Add Expense View

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var expenses: [Expense]
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("showFooters") private var showFooters: Bool = true

    @State private var name = ""
    @State private var amount: Double = 0.0
    @State private var date: Date
    @State private var showDate = false
    @State private var endDate: Date
    @State private var showEndDate = false
    @State private var isRecurring = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    @State private var recurrenceRule: RecurrenceRule = RecurrenceRule(legacy: .monthly)

    // Payment plan properties
    @State private var isMonthlyPaymentPlan = false
    @State private var totalAmount: Double = 0.0
    @State private var numberOfPayments: Int = 12

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

    enum Field: Hashable {
        case name
        case amount
        case totalAmount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isTotalAmountFocused: Bool
    @State private var hasAppeared = false

    init(expenses: Binding<[Expense]>, selectedMonth: Int? = nil, selectedYear: Int? = nil, selectedDay: Int? = nil, defaultDate: Date? = nil, item: Item? = nil) {
        self._expenses = expenses
        self.selectedMonth = selectedMonth
        self.selectedYear = selectedYear
        self.selectedDay = selectedDay
        self.defaultDate = defaultDate
        self.item = item
        let initialDate = computeInitialDate(selectedMonth: selectedMonth, selectedYear: selectedYear, selectedDay: selectedDay, defaultDate: defaultDate)
        self._date = State(initialValue: initialDate)
        self._endDate = State(initialValue: initialDate)
    }
    
    var body: some View {
        NavigationStack {
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
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(dismiss: dismiss)

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addExpense) {
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
                }
            }
            .sheet(item: $attachmentToView) { attachment in
                AttachmentViewerSheet(attachment: attachment)
            }
            .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
                dismissKeyboard()
            }
        }
    }

    private var detailsSection: some View {
        Section("Expense Details") {
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
                Text(isMonthlyPaymentPlan ? "Total Amount" : "Amount")
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
            
            PaymentAmountRow(amount: isMonthlyPaymentPlan ? (calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? 0) : 0, currencyCode: selectedCurrency.code)
                .blur(radius: isMonthlyPaymentPlan ? 0 : 5)
                .disabled(!isMonthlyPaymentPlan)

            CategoryPickerButton(selectedCategories: selectedCategories) {
                showingCategoryPicker = true
            }
        }
    }

    private var optionsSection: some View {
        Section {
            // Date picker - label changes based on mode
            // In recurring/payment plan mode: "Start Date"
            // In one-time mode: "Date"
            // When called from month view, restrict picker to that month's date range
            HStack {
                Text(isRecurring || isMonthlyPaymentPlan ? "Start Date" : "Date")
                Spacer()
                Group {
                    if let month = selectedMonth, let year = selectedYear {
                        DatePicker("", selection: $date, in: monthDateRange(month: month, year: year), displayedComponents: .date)
                    } else {
                        DatePicker("", selection: $date, displayedComponents: .date)
                    }
                }
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
                paymentPlan: PaymentPlanBindings(
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

            NumberOfPaymentsPicker(
                numberOfPayments: $numberOfPayments,
                endDate: $endDate,
                totalAmount: totalAmount,
                date: date,
                recurringFrequency: recurringFrequency,
                isEnabled: isMonthlyPaymentPlan
            )

            Toggle("End Date", isOn: $showEndDate)
                .disabled(!isRecurring || isMonthlyPaymentPlan)
                .blur(radius: (!isRecurring || isMonthlyPaymentPlan) ? 5 : 0)

            // When called from month view, restrict picker range from start date to end of month
            HStack {
                Text("End Date")
                Spacer()
                Group {
                    if let month = selectedMonth, let year = selectedYear {
                        DatePicker("", selection: $endDate, in: endDateRange(month: month, year: year, startDate: date), displayedComponents: .date)
                    } else {
                        DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                    }
                }
                .labelsHidden()
                .disabled(!showEndDate || !isRecurring || isMonthlyPaymentPlan)
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!showEndDate || !isRecurring || isMonthlyPaymentPlan)
            }
            .blur(radius: (showEndDate && isRecurring) ? 0 : 5)

        } footer: {
            if showFooters && isMonthlyPaymentPlan {
                Text("Enter the total amount and number of payments. The payment amount and end date will be calculated automatically based on the selected frequency.")
            }
        }
    }
    
    /// Dismisses both SwiftUI and UIKit keyboards
    private func dismissKeyboard() {
        focusedField = nil
        // Send resign action to UIKit responder chain for custom text fields
        resignKeyboard()
    }

    /// Creates and adds the expense to the array
    private func addExpense() {
        let finalAmount: Double
        let finalTotalAmount: Double?
        
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

        dismiss()
    }

}

// MARK: - Add Income View

struct AddIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var incomes: [Income]
    var item: Item
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("showFooters") private var showFooters: Bool = true

    @State private var name = ""
    @State private var amount: Double = 0.0
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

    var showRecurringOption: Bool = true
    var defaultShowDate: Bool = false
    var showMonthSelector: Bool = false
    
    // Date range restriction for budget page
    var budgetSelectedMonth: Int?
    var budgetSelectedYear: Int?
    var budgetSelectedDay: Int?
    var defaultDate: Date?
    
    init(incomes: Binding<[Income]>, item: Item, showRecurringOption: Bool = true, defaultShowDate: Bool = false, showMonthSelector: Bool = false, selectedMonth: Int? = nil, selectedYear: Int? = nil, selectedDay: Int? = nil, defaultDate: Date? = nil) {
        self._incomes = incomes
        self.item = item
        self.showRecurringOption = showRecurringOption
        self.defaultShowDate = defaultShowDate
        self.showMonthSelector = showMonthSelector
        self._showDate = State(initialValue: defaultShowDate)
        self.budgetSelectedMonth = selectedMonth
        self.budgetSelectedYear = selectedYear
        self.budgetSelectedDay = selectedDay
        self.defaultDate = defaultDate
        
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
    
    var body: some View {
        NavigationStack {
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
            .navigationTitle("Add Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(dismiss: dismiss)

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addIncome) {
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
                }
                if showMonthSelector {
                    updateDateForMonth()
                }
            }
            .sheet(item: $attachmentToView) { attachment in
                AttachmentViewerSheet(attachment: attachment)
            }
            .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
                dismissKeyboard()
            }
        }
    }
    
    private var detailsSection: some View {
        Section("Income Details") {
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

            CategoryPickerButton(selectedCategories: selectedCategories) {
                showingCategoryPicker = true
            }

            if item.isTaxSavingsEnabled {
                Toggle("Taxable", isOn: $isTaxable)
            }
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
            
            // Date label changes based on recurring state; only editable for recurring items
            HStack {
                Text(isRecurring ? "Start Date" : "Date")
                Spacer()
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!isRecurring)
                    .onChange(of: date) { _, newValue in
                        pickerSelectedMonth = newValue.month
                        // If end date is before new start date, update it to match
                        if showEndDate && endDate < newValue {
                            endDate = newValue
                        }
                    }
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!isRecurring)
            }
            .opacity(isRecurring ? 1.0 : 0.5)
            
            Toggle("End Date", isOn: $showEndDate)
                .disabled(!isRecurring)
                .opacity(isRecurring ? 1.0 : 0.5)

            HStack {
                Text("End Date")
                Spacer()
                DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!showEndDate || !isRecurring)
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!showEndDate || !isRecurring)
            }
            .opacity((showEndDate && isRecurring) ? 1.0 : 0.5)
        } header: {
            Text("Month")
        } footer: {
            if showFooters {
                Text("The month picker is used to categorize income — Recurring items automatically include start and end dates.")
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
                // Restrict date range to selected month when called from month details
                HStack {
                    Text(isRecurring ? "Start Date" : "Date")
                    Spacer()
                    Group {
                        if let month = budgetSelectedMonth, let year = budgetSelectedYear {
                            DatePicker("", selection: $date, in: monthDateRange(month: month, year: year), displayedComponents: .date)
                        } else {
                            DatePicker("", selection: $date, displayedComponents: .date)
                        }
                    }
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

            if !showMonthSelector {
                Toggle("End Date", isOn: $showEndDate)
                    .disabled(!isRecurring)
                    .blur(radius: isRecurring ? 0 : 5)
                    .onChange(of: showEndDate) { _, _ in
                        dismissKeyboard()
                    }

                // End date picker - restrict to selected month if applicable
                HStack {
                    Text("End Date")
                    Spacer()
                    Group {
                        if let month = budgetSelectedMonth, let year = budgetSelectedYear {
                            DatePicker("", selection: $endDate, in: endDateRange(month: month, year: year, startDate: date), displayedComponents: .date)
                        } else {
                            DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                        }
                    }
                    .labelsHidden()
                    .disabled(!showEndDate || !isRecurring)
                    DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!showEndDate || !isRecurring)
                }
                .blur(radius: (showEndDate && isRecurring) ? 0 : 5)
            }

        }
    }
    
    private func dismissKeyboard() {
        focusedField = nil
        // Force UIKit text fields to resign first responder
        resignKeyboard()
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
            categories: selectedCategories.sorted()
        )
        incomes.insert(newIncome, forSortOrder: sortOrder)
        
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
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated

    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var showDate: Bool
    @State private var endDate: Date
    @State private var showEndDate: Bool
    @State private var isRecurring: Bool
    @State private var recurringFrequency: RecurringFrequency
    @State private var recurrenceRule: RecurrenceRule

    // Payment plan properties
    @State private var isMonthlyPaymentPlan: Bool
    @State private var totalAmount: Double
    @State private var numberOfPayments: Int

    // Attachment properties
    @State private var attachments: [Attachment]
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Occurrence date for recurring edit scope
    var occurrenceDate: Date?
    var item: Item?

    // Track original recurring state
    @State private var originalIsRecurring: Bool
    @State private var originalIsMonthlyPaymentPlan: Bool

    // Track original values for change detection
    @State private var originalName: String
    @State private var originalAmount: Double
    @State private var originalDate: Date
    @State private var originalShowDate: Bool
    @State private var originalEndDate: Date?
    @State private var originalShowEndDate: Bool
    @State private var originalRecurringFrequency: RecurringFrequency
    @State private var originalRecurrenceRule: RecurrenceRule
    @State private var originalTotalAmount: Double
    @State private var originalNumberOfPayments: Int
    @State private var originalAttachments: [Attachment]

    // Category properties
    @State private var selectedCategories: Set<String>
    @State private var originalCategories: Set<String>
    @State private var showingCategoryPicker = false

    @State private var showingRecurringScopeAlert = false
    @State private var pendingRecurringScope: RecurringScope?
    @State private var showingDeleteConfirmation = false

    enum Field: Hashable {
        case name
        case amount
        case totalAmount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isTotalAmountFocused: Bool

    init(expense: Binding<Expense>, expenses: Binding<[Expense]>, occurrenceDate: Date? = nil, item: Item? = nil) {
        self._expense = expense
        self._expenses = expenses
        self.occurrenceDate = occurrenceDate
        self.item = item

        // Initialize state with current expense values to prevent flickering
        let currentExpense = expense.wrappedValue
        self._name = State(initialValue: currentExpense.name)
        self._amount = State(initialValue: currentExpense.amount)
        self._date = State(initialValue: currentExpense.date)
        self._showDate = State(initialValue: currentExpense.showDate)
        self._endDate = State(initialValue: currentExpense.endDate ?? Date())
        self._showEndDate = State(initialValue: currentExpense.showEndDate)
        self._isRecurring = State(initialValue: currentExpense.isRecurring)
        self._recurringFrequency = State(initialValue: currentExpense.recurringFrequency)
        self._recurrenceRule = State(initialValue: currentExpense.resolvedRule)
        self._isMonthlyPaymentPlan = State(initialValue: currentExpense.isMonthlyPaymentPlan)
        self._totalAmount = State(initialValue: currentExpense.totalAmount ?? 0.0)
        self._attachments = State(initialValue: currentExpense.attachments)

        // Calculate number of payments
        let calendar = Calendar.current
        var calculatedPayments = 12
        if currentExpense.isMonthlyPaymentPlan, let end = currentExpense.endDate {
            let components = calendar.dateComponents([.month], from: currentExpense.date, to: end)
            if let months = components.month, months >= 0 {
                calculatedPayments = months + 1
            }
        }
        self._numberOfPayments = State(initialValue: calculatedPayments)
        
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
        self._originalRecurrenceRule = State(initialValue: currentExpense.resolvedRule)
        self._originalTotalAmount = State(initialValue: currentExpense.totalAmount ?? 0.0)
        self._originalNumberOfPayments = State(initialValue: calculatedPayments)
        self._originalAttachments = State(initialValue: currentExpense.attachments)
        self._selectedCategories = State(initialValue: Set(currentExpense.categories))
        self._originalCategories = State(initialValue: Set(currentExpense.categories))
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(dismiss: dismiss)

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
            .sheet(item: $attachmentToView) { attachment in
                AttachmentViewerSheet(attachment: attachment)
            }
            .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
                dismissKeyboard()
            }
        }
        .recurringEditAlert(
            isPresented: $showingRecurringScopeAlert,
            pendingScope: $pendingRecurringScope,
            applyEdit: applyExpenseEdit
        )
        .background {
            AlertContainer {
                Color.clear
                    .alert("Delete Expense?", isPresented: $showingDeleteConfirmation) {
                        if originalIsRecurring || originalIsMonthlyPaymentPlan {
                            Button("Delete All Occurrences", role: .destructive) { performDeleteExpense(scope: .all) }
                            Button("Delete Current and Future", role: .destructive) { performDeleteExpense(scope: .currentAndFuture) }
                            Button("Delete Current Occurrence", role: .destructive) { performDeleteExpense(scope: .currentOnly) }
                        } else {
                            Button("Delete", role: .destructive) { performDeleteExpense(scope: nil) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if originalIsRecurring || originalIsMonthlyPaymentPlan {
                            Text("This is a recurring item. Choose which occurrences to delete:")
                        } else {
                            Text("This will permanently delete '\(expense.name)'. This action cannot be undone.")
                        }
                    }
            }
        }
    }

    private var detailsSection: some View {
        Section("Expense Details") {
            titleField
            amountField

            paymentAmountField
                .blur(radius: isMonthlyPaymentPlan ? 0 : 5)
                .disabled(!isMonthlyPaymentPlan)

            CategoryPickerButton(selectedCategories: selectedCategories) {
                showingCategoryPicker = true
            }
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
            Text(isMonthlyPaymentPlan ? "Total Amount" : "Amount")
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
        PaymentAmountRow(amount: isMonthlyPaymentPlan ? (calculatePaymentAmount(total: totalAmount, payments: numberOfPayments) ?? 0) : 0, currencyCode: selectedCurrency.code)
    }
    
    private var optionsSection: some View {
        Section {
            startDatePicker
            frequencyPicker
            NumberOfPaymentsPicker(
                numberOfPayments: $numberOfPayments,
                endDate: $endDate,
                totalAmount: totalAmount,
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
            paymentPlan: PaymentPlanBindings(
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
    
    private var endDatePicker: some View {
        Group {
            // Edit views should not restrict date range - only Add views restrict dates when called from month sheets
            HStack {
                Text("End Date")
                Spacer()
                DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!showEndDate || !isRecurring || isMonthlyPaymentPlan)
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!showEndDate || !isRecurring || isMonthlyPaymentPlan)
            }
            .blur(radius: (showEndDate && isRecurring) ? 0 : 5)
        }
    }
    
    private var endDateToggle: some View {
        Toggle("End Date", isOn: $showEndDate)
            .disabled(!isRecurring || isMonthlyPaymentPlan)
            .blur(radius: (!isRecurring || isMonthlyPaymentPlan) ? 5 : 0)
    }
    
    private func dismissKeyboard() {
        focusedField = nil
        resignKeyboard()
    }

    /// Checks if changes were made and determines edit scope for recurring items
    /// Shows alert for multi-occurrence recurring items, bypasses alert for single occurrences
    /// Payment plan items always edit all occurrences without showing the scope alert
    private func checkAndSaveExpense() {
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
    
    private func computePaymentAmounts() -> (amount: Double, totalAmount: Double?) {
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
        if let scope = scope {
            var pendingScope: RecurringScope? = scope
            var adjustedExpense = expense
            if let occ = occurrenceDate, scope == .currentAndFuture || scope == .currentOnly {
                adjustedExpense.date = occ
            }
            applyRecurringItemDeletion(item: adjustedExpense, items: &expenses, pendingScope: &pendingScope)
        } else {
            expenses.removeAll { $0.id == expense.id }
        }
        dismiss()
    }
    
}

// MARK: - Edit Income View (for Budget Page)

struct EditIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var income: Income
    @Binding var incomes: [Income]
    var item: Item
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated

    @State private var name: String
    @State private var amount: Double
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

    // Track original recurring state
    @State private var originalIsRecurring: Bool

    // Track original values for change detection
    @State private var originalName: String
    @State private var originalAmount: Double
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

    enum Field: Hashable {
        case name
        case amount
    }

    @FocusState private var focusedField: Field?
    @FocusState private var isAmountFocused: Bool

    init(income: Binding<Income>, incomes: Binding<[Income]>, item: Item, occurrenceDate: Date? = nil) {
        self._income = income
        self._incomes = incomes
        self.item = item
        self.occurrenceDate = occurrenceDate
        
        // Initialize state with current income values to prevent flickering
        let currentIncome = income.wrappedValue
        self._name = State(initialValue: currentIncome.name)
        self._amount = State(initialValue: currentIncome.amount)
        self._date = State(initialValue: currentIncome.date)
        self._showDate = State(initialValue: currentIncome.showDate)
        self._endDate = State(initialValue: currentIncome.endDate ?? Date())
        self._showEndDate = State(initialValue: currentIncome.showEndDate)
        self._isRecurring = State(initialValue: currentIncome.isRecurring)
        self._recurringFrequency = State(initialValue: currentIncome.recurringFrequency)
        self._recurrenceRule = State(initialValue: currentIncome.resolvedRule)
        self._attachments = State(initialValue: currentIncome.attachments)
        self._isTaxable = State(initialValue: currentIncome.isTaxable)

        // Store original values
        self._originalIsRecurring = State(initialValue: currentIncome.isRecurring)
        self._originalName = State(initialValue: currentIncome.name)
        self._originalAmount = State(initialValue: currentIncome.amount)
        self._originalDate = State(initialValue: currentIncome.date)
        self._originalShowDate = State(initialValue: currentIncome.showDate)
        self._originalEndDate = State(initialValue: currentIncome.endDate)
        self._originalShowEndDate = State(initialValue: currentIncome.showEndDate)
        self._originalRecurringFrequency = State(initialValue: currentIncome.recurringFrequency)
        self._originalRecurrenceRule = State(initialValue: currentIncome.resolvedRule)
        self._originalIsTaxable = State(initialValue: currentIncome.isTaxable)
        self._originalAttachments = State(initialValue: currentIncome.attachments)
        self._selectedCategories = State(initialValue: Set(currentIncome.categories))
        self._originalCategories = State(initialValue: Set(currentIncome.categories))
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
        NavigationStack {
            Form {
                Section("Income Details") {
                    titleField
                    amountField

                    CategoryPickerButton(selectedCategories: selectedCategories) {
                        showingCategoryPicker = true
                    }

                    if item.isTaxSavingsEnabled {
                        Toggle("Taxable", isOn: $isTaxable)
                    }
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

                    Toggle("End Date", isOn: $showEndDate)
                        .disabled(!isRecurring)
                        .blur(radius: isRecurring ? 0 : 5)

                    // End date picker
                    HStack {
                        Text("End Date")
                        Spacer()
                        DatePicker("", selection: $endDate, in: date..., displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!showEndDate || !isRecurring)
                        DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .disabled(!showEndDate || !isRecurring)
                    }
                    .blur(radius: (showEndDate && isRecurring) ? 0 : 5)
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
            .navigationTitle("Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CancelToolbarItem(dismiss: dismiss)

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
            .sheet(item: $attachmentToView) { attachment in
                AttachmentViewerSheet(attachment: attachment)
            }
            .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments) {
                dismissKeyboard()
            }
        }
        .recurringEditAlert(
            isPresented: $showingRecurringScopeAlert,
            pendingScope: $pendingRecurringScope,
            applyEdit: applyIncomeEdit
        )
        .background {
            AlertContainer {
                Color.clear
                    .alert("Delete Income?", isPresented: $showingDeleteConfirmation) {
                        if originalIsRecurring {
                            Button("Delete All Occurrences", role: .destructive) { performDeleteIncome(scope: .all) }
                            Button("Delete Current and Future", role: .destructive) { performDeleteIncome(scope: .currentAndFuture) }
                            Button("Delete Current Occurrence", role: .destructive) { performDeleteIncome(scope: .currentOnly) }
                        } else {
                            Button("Delete", role: .destructive) { performDeleteIncome(scope: nil) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if originalIsRecurring {
                            Text("This is a recurring item. Choose which occurrences to delete:")
                        } else {
                            Text("This will permanently delete '\(income.name)'. This action cannot be undone.")
                        }
                    }
            }
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        resignKeyboard()
    }

    private func checkAndSaveIncome() {
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
            categories: selectedCategories.sorted()
        )
    }

    private func saveIncome() {
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
        income.categories = selectedCategories.sorted()

        // Force array modification to trigger onChange by replacing the income in the array
        if let index = incomes.firstIndex(where: { $0.id == income.id }) {
            incomes[index] = income
            print("✅ EditIncomeView: Changes saved for income '\(name)'")
        }

        dismiss()
    }

    private func performDeleteIncome(scope: RecurringScope?) {
        if let scope = scope {
            var pendingScope: RecurringScope? = scope
            var adjustedIncome = income
            if let occ = occurrenceDate, scope == .currentAndFuture || scope == .currentOnly {
                adjustedIncome.date = occ
            }
            applyRecurringItemDeletion(item: adjustedIncome, items: &incomes, pendingScope: &pendingScope)
        } else {
            incomes.removeAll { $0.id == income.id }
        }
        dismiss()
    }
    
}

