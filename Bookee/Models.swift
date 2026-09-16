//
//  Models.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import Foundation
import SwiftData

// MARK: - Item Type

enum ItemType: String, Codable {
    case budget = "Budget"
    case income = "Income"
}

// MARK: - Item Model

@Model
final class Item {
    var timestamp: Date
    var lastOpenedDate: Date
    var lastModifiedDate: Date
    var name: String
    var manualSortOrder: Int
    var taxSavingsPercentage: Double
    var isTaxSavingsEnabled: Bool
    var lastTaxSavingsPercentage: Double?  // Stores the last non-zero tax savings percentage to allow restoring when re-enabled
    var itemType: ItemType
    var targetYear: Int?
    var deletedDate: Date?  // Timestamp when the item was soft-deleted; nil indicates the item is active

    // Monthly overview display settings (optional for backward compatibility)
    var hideExpensesRow: Bool?  // When true, hides the Expenses row in monthly overview displays
    var hideTaxesGoalRow: Bool?  // When true, hides the Taxes/Goal row in monthly overview displays
    var hideReallocationsRow: Bool?  // When true, hides the Reallocations row in monthly overview displays
    var hideIncomeSurplusRow: Bool?  // When true, hides the Income Surplus/Deficit row in monthly overview displays
    var hideOtherIncomeRow: Bool?  // When true, hides the Other Income row and merges its amount into the Taxable Income row (renamed "Income")
    var hiddenFilterCategories: String?  // JSON-encoded [String] of category names hidden from the filter sheet for this budget

    var calendarWeekStartDay: Int?  // 1 = Sunday, 2 = Monday; nil = Sunday

    // Transient property to track unsaved duplicate items in memory (not persisted to SwiftData)
    @Transient var isUnsavedDuplicate: Bool = false

    var effectiveLastTaxSavingsPercentage: Double { lastTaxSavingsPercentage ?? 0.0 }

    var effectiveShowExpensesRow: Bool { !(hideExpensesRow ?? false) }
    var effectiveShowTaxesGoalRow: Bool { !(hideTaxesGoalRow ?? false) }
    var effectiveShowReallocationsRow: Bool { !(hideReallocationsRow ?? false) }
    var effectiveShowIncomeSurplusRow: Bool { !(hideIncomeSurplusRow ?? false) }
    var effectiveShowOtherIncomeRow: Bool { effectiveShowTaxesGoalRow }
    var effectiveCalendarWeekStartDay: Int { calendarWeekStartDay ?? 1 }

    // External storage attributes for related data (encoded as binary Data)
    @Attribute(.externalStorage) var expensesData: Data?
    @Attribute(.externalStorage) var incomesData: Data?
    @Attribute(.externalStorage) var attachmentsData: Data?
    @Attribute(.externalStorage) var reallocationsData: Data?
    @Attribute(.externalStorage) var odometerReadingsData: Data?

    init(timestamp: Date, name: String = "", manualSortOrder: Int = 0, taxSavingsPercentage: Double = 0.0, isTaxSavingsEnabled: Bool = true, itemType: ItemType = .budget, targetYear: Int? = nil) {
        self.timestamp = timestamp
        self.lastOpenedDate = timestamp
        self.lastModifiedDate = timestamp
        self.name = name
        self.manualSortOrder = manualSortOrder
        self.taxSavingsPercentage = taxSavingsPercentage.roundedMoney()
        self.isTaxSavingsEnabled = isTaxSavingsEnabled
        self.lastTaxSavingsPercentage = taxSavingsPercentage.isEffectivelyPositive ? taxSavingsPercentage.roundedMoney() : nil
        self.itemType = itemType
        self.targetYear = targetYear
        self.deletedDate = nil
        self.expensesData = nil
        self.incomesData = nil
        self.attachmentsData = nil
        self.reallocationsData = nil
        self.odometerReadingsData = nil
    }

    /// Display name with a sensible fallback for items that haven't been named yet.
    var displayName: String { name.isEmpty ? "Budget" : name }

    var trashDisplayName: String { name.isEmpty ? "New Budget" : name }

    /// Tax rate as an exact base-10 Decimal (e.g. 11.5% → 0.115 exactly).
    /// Converted via shortest-round-trip String to avoid Decimal(Double)'s FP residue.
    /// With Decimal, 1 - taxRate at 99.99% is exactly 0.0001 and at 100% is exactly 0,
    /// so the income-needed divisor guard is a clean == 0 check.
    var taxRate: Decimal {
        taxRateDecimal(fromPercentage: taxSavingsPercentage)
    }

    /// True when tax savings is both enabled and has a positive percentage.
    var isTaxActive: Bool {
        isTaxSavingsActive(isTaxSavingsEnabled: isTaxSavingsEnabled, taxSavingsPercentage: taxSavingsPercentage)
    }

    var isDeleted: Bool { deletedDate != nil }

    /// Returns the number of days remaining before permanent deletion (nil if not deleted).
    /// Items are permanently deleted 30 days after soft deletion.
    var daysUntilPermanentDeletion: Int? {
        guard let deletedDate = deletedDate else { return nil }
        let daysSinceDeletion = Calendar.current.dateComponents([.day], from: deletedDate, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }

    /// Decodes expenses/incomes/reallocations/odometer readings, skipping the (often much larger)
    /// attachments blob. Callers that only need counts or dates — like category/type filter
    /// tallies — should use this instead of `decodeBudgetData()` so they don't pay to base64-decode
    /// every embedded photo/PDF just to throw the result away.
    /// Returns nil if expensesData or incomesData are absent (indicates a new/empty item).
    func decodeBudgetDataExcludingAttachments() -> (expenses: [Expense], incomes: [Income], reallocations: [Reallocation], odometerReadings: [OdometerReading])? {
        guard let expensesData, let incomesData else { return nil }
        let expenses         = (try? JSONDecoder().decode([Expense].self,          from: expensesData))     ?? []
        let incomes          = (try? JSONDecoder().decode([Income].self,           from: incomesData))      ?? []
        let reallocations    = reallocationsData.flatMap     { try? JSONDecoder().decode([Reallocation].self,     from: $0) } ?? []
        let odometerReadings = odometerReadingsData.flatMap  { try? JSONDecoder().decode([OdometerReading].self,  from: $0) } ?? []
        return (expenses, incomes, reallocations, odometerReadings)
    }

    /// Decodes all five budget arrays from the item's stored data fields.
    /// Returns nil if expensesData or incomesData are absent (indicates a new/empty item).
    func decodeBudgetData() -> (expenses: [Expense], incomes: [Income], attachments: [BudgetAttachment], reallocations: [Reallocation], odometerReadings: [OdometerReading])? {
        guard let base = decodeBudgetDataExcludingAttachments() else { return nil }
        let attachments = attachmentsData.flatMap { try? JSONDecoder().decode([BudgetAttachment].self, from: $0) } ?? []
        return (base.expenses, base.incomes, attachments, base.reallocations, base.odometerReadings)
    }

    /// Encodes all five budget arrays into the item's external-storage data fields.
    func encodeBudgetData(expenses: [Expense], incomes: [Income], attachments: [BudgetAttachment], reallocations: [Reallocation], odometerReadings: [OdometerReading]) throws {
        expensesData         = try JSONEncoder().encode(expenses)
        incomesData          = try JSONEncoder().encode(incomes)
        attachmentsData      = try JSONEncoder().encode(attachments)
        reallocationsData    = try JSONEncoder().encode(reallocations)
        odometerReadingsData = try JSONEncoder().encode(odometerReadings)
    }
}

// MARK: - Recurring Item Protocol

/// Shared interface for recurring transactions (Expense, Income) that can be split or edited by scope.
/// Used by the generic `applyRecurringItemEdit` helper in AddEditViews.swift.
nonisolated protocol RecurringItem: Identifiable {
    var id: UUID { get }
    var amount: Decimal { get }
    var date: Date { get set }
    var endDate: Date? { get set }
    var showEndDate: Bool { get set }
    var isRecurring: Bool { get set }
    var effectiveFrequency: String { get }
    /// The resolved RecurrenceRule for this item. Used by the occurrence engine.
    var resolvedRule: RecurrenceRule { get }
    var createdAt: Date { get }
    /// True when the item counts as recurring for deletion/edit scope logic.
    /// Defaults to `isRecurring`; `Expense` overrides to also include `isMonthlyPaymentPlan`.
    var isEffectivelyRecurring: Bool { get }
    func duplicate() -> Self
}

nonisolated extension RecurringItem {
    var isEffectivelyRecurring: Bool { isRecurring }

    func withOccurrenceDate(day: Int, month: Int, year: Int) -> Self? {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = calendar.component(.hour, from: date)
        comps.minute = calendar.component(.minute, from: date)
        guard let occurrenceDate = calendar.date(from: comps) else { return nil }
        var copy = self
        copy.date = occurrenceDate
        return copy
    }
}

// MARK: - Recurring Scope

/// Defines which occurrences are affected when editing, deleting, or duplicating a recurring item.
enum RecurringScope {
    case currentOnly
    case currentAndFuture
    case all
}

// MARK: - Shared Recurring Frequency

enum RecurringFrequency: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Bi-weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
}

// MARK: - Recurrence Rule

nonisolated enum RecurrenceUnit: String, Codable {
    case day, week, month, year
}

nonisolated enum MonthlyPattern: Equatable, Hashable {
    /// Repeat on specific calendar days of the month. Empty set = derive from start date (legacy).
    case dayOfMonth(days: Set<Int>)
    case nthWeekday(weeks: Set<Int>, weekdays: Set<Int>)
}

extension MonthlyPattern: Codable {
    enum CodingKeys: String, CodingKey { case type, weeks, weekdays, week, weekday, days }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "nthWeekday" {
            if let weeksArray = try container.decodeIfPresent([Int].self, forKey: .weeks) {
                let weekdaysArray = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
                self = .nthWeekday(weeks: Set(weeksArray), weekdays: Set(weekdaysArray))
            } else {
                // Migrate old single-value format
                let week = try container.decode(Int.self, forKey: .week)
                let weekday = try container.decode(Int.self, forKey: .weekday)
                self = .nthWeekday(weeks: [week], weekdays: [weekday])
            }
        } else {
            let daysArray = try container.decodeIfPresent([Int].self, forKey: .days) ?? []
            self = .dayOfMonth(days: Set(daysArray))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dayOfMonth(let days):
            try container.encode("dayOfMonth", forKey: .type)
            try container.encode(Array(days).sorted(), forKey: .days)
        case .nthWeekday(let weeks, let weekdays):
            try container.encode("nthWeekday", forKey: .type)
            try container.encode(Array(weeks).sorted(), forKey: .weeks)
            try container.encode(Array(weekdays).sorted(), forKey: .weekdays)
        }
    }
}

nonisolated struct RecurrenceRule: Equatable, Hashable {
    var unit: RecurrenceUnit
    var interval: Int
    var weekdays: Set<Int>
    var monthlyPattern: MonthlyPattern

    init(unit: RecurrenceUnit, interval: Int = 1, weekdays: Set<Int> = [], monthlyPattern: MonthlyPattern = .dayOfMonth(days: [])) {
        self.unit = unit
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.monthlyPattern = monthlyPattern
    }

    init(legacy: RecurringFrequency) {
        switch legacy {
        case .daily:     self.init(unit: .day,   interval: 1)
        case .weekly:    self.init(unit: .week,  interval: 1)
        case .biweekly:  self.init(unit: .week,  interval: 2)
        case .monthly:   self.init(unit: .month, interval: 1)
        case .quarterly: self.init(unit: .month, interval: 3)
        case .yearly:    self.init(unit: .year,  interval: 1)
        }
    }

    var closestLegacyFrequency: RecurringFrequency {
        switch unit {
        case .day:   return .daily
        case .week:  return interval >= 2 ? .biweekly : .weekly
        case .month: return interval >= 3 ? .quarterly : .monthly
        case .year:  return .yearly
        }
    }
}

extension RecurrenceRule: Codable {
    enum CodingKeys: String, CodingKey { case unit, interval, weekdays, monthlyPattern }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unit = try container.decode(RecurrenceUnit.self, forKey: .unit)
        interval = max(1, (try container.decodeIfPresent(Int.self, forKey: .interval)) ?? 1)
        let weekdaysArray = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        weekdays = Set(weekdaysArray)
        monthlyPattern = try container.decodeIfPresent(MonthlyPattern.self, forKey: .monthlyPattern) ?? .dayOfMonth(days: [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(unit, forKey: .unit)
        try container.encode(interval, forKey: .interval)
        try container.encode(Array(weekdays).sorted(), forKey: .weekdays)
        try container.encode(monthlyPattern, forKey: .monthlyPattern)
    }
}

nonisolated extension RecurrenceRule {
    /// Selected days-of-month for a monthly `.dayOfMonth` pattern.
    /// Empty set = derive the day from the start date (legacy behavior).
    var monthDays: Set<Int> {
        get {
            if case .dayOfMonth(let days) = monthlyPattern { return days }
            return []
        }
        set { monthlyPattern = .dayOfMonth(days: newValue) }
    }
}

nonisolated extension RecurrenceRule {
    /// Returns true if this recurring item occurs on `checkDate`.
    /// Bounds checks (start/end date) are handled by the CALLER.
    func occurs(onDay checkDate: Date, startDate: Date) -> Bool {
        let calendar = Calendar.current
        guard let normalizedStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: startDate)),
              let normalizedCheck = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: checkDate)) else { return false }
        guard normalizedCheck >= normalizedStart else { return false }
        let ivl = max(1, interval)
        switch unit {
        case .day:
            let daysDiff = calendar.dateComponents([.day], from: normalizedStart, to: normalizedCheck).day ?? 0
            return daysDiff % ivl == 0
        case .week:
            let startWeekday = calendar.component(.weekday, from: startDate)
            let checkWeekday = calendar.component(.weekday, from: checkDate)
            let targetWeekdays = weekdays.isEmpty ? Set([startWeekday]) : weekdays
            guard targetWeekdays.contains(checkWeekday) else { return false }
            let compsForStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: normalizedStart)
            let compsForCheck = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: normalizedCheck)
            guard let weekStart = calendar.date(from: compsForStart),
                  let weekCheck = calendar.date(from: compsForCheck) else { return false }
            let weeksDiff = calendar.dateComponents([.weekOfYear], from: weekStart, to: weekCheck).weekOfYear ?? 0
            return weeksDiff % ivl == 0
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: normalizedStart, to: normalizedCheck)
            let totalMonths = (comps.year ?? 0) * 12 + (comps.month ?? 0)
            guard totalMonths % ivl == 0 else { return false }
            switch monthlyPattern {
            case .dayOfMonth(let days):
                let daysInCheckMonth = calendar.range(of: .day, in: .month, for: checkDate)?.count ?? 30
                let checkDay = calendar.component(.day, from: checkDate)
                if days.isEmpty {
                    // Legacy: single day derived from the start date.
                    if startDate.isLastDayOfMonth { return checkDate.isLastDayOfMonth }
                    let startDay = calendar.component(.day, from: startDate)
                    return checkDay == min(startDay, daysInCheckMonth)
                }
                // Sentinel 32 = last day of the month
                if days.contains(32) && checkDay == daysInCheckMonth { return true }
                let regularDays = days.filter { $0 != 32 }
                let targetDays = Set(regularDays.map { min($0, daysInCheckMonth) })
                return targetDays.contains(checkDay)
            case .nthWeekday(let weeks, let weekdays):
                let checkWeekday = calendar.component(.weekday, from: checkDate)
                if !weekdays.isEmpty && !weekdays.contains(checkWeekday) { return false }
                if !weeks.isEmpty {
                    let checkDay = calendar.component(.day, from: checkDate)
                    let daysInMonth = calendar.range(of: .day, in: .month, for: checkDate)?.count ?? 30
                    let isLastWeek = checkDay + 7 > daysInMonth
                    let weekNum = (checkDay - 1) / 7 + 1
                    if !weeks.contains(weekNum) && !(isLastWeek && weeks.contains(-1)) { return false }
                }
                return true
            }
        case .year:
            let startMonth = calendar.component(.month, from: startDate)
            let startDay = calendar.component(.day, from: startDate)
            let checkMonth = calendar.component(.month, from: checkDate)
            let checkDay = calendar.component(.day, from: checkDate)
            let comps = calendar.dateComponents([.year, .month], from: normalizedStart, to: normalizedCheck)
            let totalMonths = (comps.year ?? 0) * 12 + (comps.month ?? 0)
            guard totalMonths % 12 == 0, (totalMonths / 12) % ivl == 0 else { return false }
            if startDate.isLastDayOfMonth {
                return startMonth == checkMonth && checkDate.isLastDayOfMonth
            } else {
                guard startMonth == checkMonth else { return false }
                let daysInCheckMonth = calendar.range(of: .day, in: .month, for: checkDate)?.count ?? 30
                return checkDay == min(startDay, daysInCheckMonth)
            }
        }
    }

    /// Returns the next occurrence date after `date`, given the item's `startDate` (for day/week alignment).
    func nextOccurrence(after date: Date, startDate: Date) -> Date? {
        let calendar = Calendar.current
        let ivl = max(1, interval)
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: ivl, to: date)
        case .week:
            var current = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let maxScan = ivl * 7 + 14
            for _ in 0..<maxScan {
                if occurs(onDay: current, startDate: startDate) { return current }
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
            return calendar.date(byAdding: .weekOfYear, value: ivl, to: date)
        case .month:
            // Scan day-by-day so multiple selected days within the same interval month are found in order.
            var current = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let maxScan = ivl * 31 + 62
            for _ in 0..<maxScan {
                if occurs(onDay: current, startDate: startDate) { return current }
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
            return calendar.date(byAdding: .month, value: ivl, to: date)
        case .year:
            let isLastDay = startDate.isLastDayOfMonth
            let startMonth = calendar.component(.month, from: startDate)
            let startDay = calendar.component(.day, from: startDate)
            var current = date
            for _ in 0..<5 {
                guard let next = calendar.date(byAdding: .year, value: ivl, to: current) else { return nil }
                let yr = calendar.component(.year, from: next)
                if let firstOfMonth = calendar.date(from: DateComponents(year: yr, month: startMonth, day: 1)),
                   let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count {
                    let targetDay = isLastDay ? daysInMonth : min(startDay, daysInMonth)
                    if let result = calendar.date(from: DateComponents(year: yr, month: startMonth, day: targetDay)) { return result }
                }
                current = next
            }
            return nil
        }
    }
}

// MARK: - Expense Model
// Represents a financial expense with support for one-time or recurring charges,
// monthly payment plans (splitting a total amount across months), and file attachments

nonisolated struct Expense: Identifiable, Equatable, Hashable, RecurringItem {
    let id: UUID
    var name: String
    var amount: Decimal
    var date: Date
    var showDate: Bool
    var endDate: Date?
    var showEndDate: Bool
    var isRecurring: Bool
    var recurringFrequency: RecurringFrequency
    var recurrenceRule: RecurrenceRule?

    // Monthly payment plan properties: enables splitting a total cost across multiple months
    var isMonthlyPaymentPlan: Bool
    var totalAmount: Decimal?
    
    // File attachments (receipts, invoices, etc.)
    var attachments: [Attachment]
    
    // Timestamp when this expense was created (for sorting items with same date)
    var createdAt: Date

    // User-defined categories for filtering (empty array means uncategorized)
    var categories: [String]

    // ID of the income created when this expense was reimbursed (nil if not yet reimbursed)
    var reimbursedByIncomeId: UUID?

    // Soft-delete: set when moved to trash, nil when active
    var deletedDate: Date?

    var daysUntilTrashDeletion: Int? {
        guard let deletedDate else { return nil }
        let daysSinceDeletion = Calendar.current.dateComponents([.day], from: deletedDate, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }

    init(id: UUID = UUID(), name: String, amount: Decimal, date: Date, showDate: Bool = false, endDate: Date? = nil, showEndDate: Bool = false, isRecurring: Bool, recurringFrequency: RecurringFrequency, recurrenceRule: RecurrenceRule? = nil, isMonthlyPaymentPlan: Bool = false, totalAmount: Decimal? = nil, attachments: [Attachment] = [], createdAt: Date = Date(), categories: [String] = [], reimbursedByIncomeId: UUID? = nil, deletedDate: Date? = nil) {
        self.id = id
        self.name = name
        self.amount = amount.roundedMoney()
        self.date = date
        self.showDate = showDate
        self.endDate = endDate
        self.showEndDate = showEndDate
        self.isRecurring = isRecurring
        self.recurringFrequency = recurringFrequency
        self.recurrenceRule = recurrenceRule
        self.isMonthlyPaymentPlan = isMonthlyPaymentPlan
        self.totalAmount = totalAmount?.roundedMoney()
        self.attachments = attachments
        self.createdAt = createdAt
        self.categories = categories
        self.reimbursedByIncomeId = reimbursedByIncomeId
        self.deletedDate = deletedDate
    }

    /// Effective recurring frequency string, using "Monthly" for payment plans.
    /// Payment plans always behave monthly regardless of the stored frequency.
    var effectiveFrequency: String { isMonthlyPaymentPlan ? "Monthly" : recurringFrequency.rawValue }

    /// Resolved recurrence rule: payment plans force monthly; otherwise use stored rule or derive from legacy frequency.
    var resolvedRule: RecurrenceRule {
        if isMonthlyPaymentPlan { return RecurrenceRule(unit: .month, interval: 1) }
        return recurrenceRule ?? RecurrenceRule(legacy: recurringFrequency)
    }

    var isEffectivelyRecurring: Bool { isRecurring || isMonthlyPaymentPlan }

    /// Computes the base payment and remainder cents using the largest-remainder method.
    /// Used by both monthlyPaymentAmount() and paymentAmount(forPaymentNumber:) to avoid duplication.
    /// - Returns: (baseAmount per payment, number of payments that receive an extra cent)
    private func largestRemainderBase(total: Decimal, monthCount: Int) -> (baseAmount: Decimal, centsNeeded: Int) {
        let baseAmount = floorCentsPerPayment(total: total, payments: monthCount) ?? 0
        let totalCents = NSDecimalNumber(decimal: total.roundedMoney() * 100).int64Value
        let centsPerPayment = NSDecimalNumber(decimal: baseAmount * 100).int64Value
        let centsNeeded = totalCents - (centsPerPayment * Int64(monthCount))
        return (baseAmount, Int(centsNeeded))
    }

    /// Calculates the monthly payment amount by dividing the total amount across all months
    /// in the payment plan period (inclusive of both start and end months).
    /// Uses the largest remainder method to ensure all payments sum exactly to the total.
    /// Returns nil if this is not a monthly payment plan or required data is missing.
    func monthlyPaymentAmount() -> Decimal? {
        guard isMonthlyPaymentPlan,
              let total = totalAmount,
              let end = endDate else {
            return nil
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: date, to: end)
        guard let months = components.month, months > 0 else {
            return total.roundedMoney()
        }

        let (baseAmount, _) = largestRemainderBase(total: total, monthCount: months + 1)
        return baseAmount
    }
    
    /// Calculates the exact payment amount for a specific payment number in the plan.
    /// Uses the largest remainder method to distribute cents fairly across all payments.
    /// - Parameter paymentNumber: The payment index (1-based, where 1 is the first payment)
    /// - Returns: The exact payment amount for this payment, or nil if invalid
    func paymentAmount(forPaymentNumber paymentNumber: Int) -> Decimal? {
        guard isMonthlyPaymentPlan,
              let total = totalAmount,
              let end = endDate else {
            return nil
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: date, to: end)
        guard let months = components.month, months > 0 else {
            return paymentNumber == 1 ? total.roundedMoney() : nil
        }

        let monthCount = months + 1
        guard paymentNumber >= 1 && paymentNumber <= monthCount else { return nil }

        let (baseAmount, centsNeeded) = largestRemainderBase(total: total, monthCount: monthCount)
        let extraCent: Decimal = paymentNumber <= centsNeeded ? (Decimal(1) / 100) : 0
        return roundMoney(baseAmount + extraCent)
    }
    
    /// Returns the total number of monthly payments in the payment plan period.
    /// Includes both the start month and end month in the count.
    /// Returns nil if this is not a monthly payment plan or end date is missing.
    func totalPayments() -> Int? {
        guard isMonthlyPaymentPlan,
              let end = endDate else {
            return nil
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: date, to: end)
        guard let months = components.month else {
            return 1
        }
        
        // Add 1 to include both start and end months
        return months + 1
    }
}

// MARK: - Shared Category Decode Helper

/// Decodes a `categories` field that may be stored as a `[String]` array (current format)
/// or a legacy single `String` value. Returns an empty array if neither key is present.
private func decodeCategories<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    arrayKey: K,
    legacyKey: K
) throws -> [String] {
    if let cats = try container.decodeIfPresent([String].self, forKey: arrayKey) { return cats }
    if let single = try container.decodeIfPresent(String.self, forKey: legacyKey), !single.isEmpty { return [single] }
    return []
}

// MARK: - Expense Codable Implementation
// Custom Codable implementation to handle backward compatibility for legacy data
// that may be missing newer properties like monthly payment plans and attachments

extension Expense: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, amount, date, showDate, endDate, showEndDate
        case isRecurring, recurringFrequency, recurrenceRule
        case isMonthlyPaymentPlan, totalAmount
        case attachments
        case createdAt
        case categories
        case category // legacy key for backward compatibility
        case reimbursedByIncomeId
        case deletedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decodeMoney(forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        showDate = try container.decode(Bool.self, forKey: .showDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        showEndDate = try container.decode(Bool.self, forKey: .showEndDate)
        isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
        recurringFrequency = try container.decode(RecurringFrequency.self, forKey: .recurringFrequency)
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)

        // Backward compatibility: default to false/nil if monthly payment plan properties are missing
        isMonthlyPaymentPlan = try container.decodeIfPresent(Bool.self, forKey: .isMonthlyPaymentPlan) ?? false
        totalAmount = try container.decodeMoneyIfPresent(forKey: .totalAmount)

        // Backward compatibility: default to empty array if attachments are missing
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []

        // Backward compatibility: use date if createdAt is missing (for existing data)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? date

        categories = try decodeCategories(from: container, arrayKey: .categories, legacyKey: .category)
        reimbursedByIncomeId = try container.decodeIfPresent(UUID.self, forKey: .reimbursedByIncomeId)
        deletedDate = try container.decodeIfPresent(Date.self, forKey: .deletedDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encode(showDate, forKey: .showDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(showEndDate, forKey: .showEndDate)
        try container.encode(isRecurring, forKey: .isRecurring)
        try container.encode(recurringFrequency, forKey: .recurringFrequency)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encode(isMonthlyPaymentPlan, forKey: .isMonthlyPaymentPlan)
        try container.encodeIfPresent(totalAmount, forKey: .totalAmount)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(categories, forKey: .categories)
        try container.encodeIfPresent(reimbursedByIncomeId, forKey: .reimbursedByIncomeId)
        try container.encodeIfPresent(deletedDate, forKey: .deletedDate)
    }
}


// MARK: - Expense Duplication

nonisolated extension Expense {
    /// Returns a copy of this expense with a fresh ID and new IDs on all attachments.
    /// Used for single-item duplication and recurring splits, where the copy should always
    /// start out active (never trashed) and unlinked from any reimbursement income.
    func duplicate() -> Expense {
        Expense(
            id: UUID(),
            name: name,
            amount: amount,
            date: date,
            showDate: showDate,
            endDate: endDate,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: totalAmount,
            attachments: attachments.map { $0.withNewID() },
            createdAt: createdAt,
            categories: categories
        )
    }

    /// Returns a faithful copy of this expense for whole-budget duplication: fresh ID and
    /// attachment IDs, but preserves `deletedDate` (so a trashed expense stays trashed in the
    /// copy) and remaps `reimbursedByIncomeId` through `incomeIDMap` so the link points at the
    /// copied income (or nil if that income wasn't carried over into the map).
    func duplicateForBudgetCopy(incomeIDMap: [UUID: UUID]) -> Expense {
        Expense(
            id: UUID(),
            name: name,
            amount: amount,
            date: date,
            showDate: showDate,
            endDate: endDate,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            isMonthlyPaymentPlan: isMonthlyPaymentPlan,
            totalAmount: totalAmount,
            attachments: attachments.map { $0.withNewID() },
            createdAt: createdAt,
            categories: categories,
            reimbursedByIncomeId: reimbursedByIncomeId.flatMap { incomeIDMap[$0] },
            deletedDate: deletedDate
        )
    }
}

// MARK: - Income Model
// Represents a financial income source with support for one-time or recurring payments,
// taxability tracking, and file attachments

nonisolated struct Income: Identifiable, Equatable, Hashable, RecurringItem {
    let id: UUID
    var name: String
    var amount: Decimal
    var date: Date
    var showDate: Bool
    var endDate: Date?
    var showEndDate: Bool
    var isRecurring: Bool
    var recurringFrequency: RecurringFrequency
    var recurrenceRule: RecurrenceRule?
    var attachments: [Attachment]
    var isTaxable: Bool  // Tracks whether this income is subject to taxation
    var taxPercentageOverride: Decimal?  // nil = use the budget's default tax percentage

    // Timestamp when this income was created (for sorting items with same date)
    var createdAt: Date

    // User-defined categories for filtering (empty array means uncategorized)
    var categories: [String]

    // Soft-delete: set when moved to trash, nil when active
    var deletedDate: Date?

    var daysUntilTrashDeletion: Int? {
        guard let deletedDate else { return nil }
        let daysSinceDeletion = Calendar.current.dateComponents([.day], from: deletedDate, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }

    init(id: UUID = UUID(), name: String, amount: Decimal, date: Date, showDate: Bool = false, endDate: Date? = nil, showEndDate: Bool = false, isRecurring: Bool, recurringFrequency: RecurringFrequency, recurrenceRule: RecurrenceRule? = nil, attachments: [Attachment] = [], isTaxable: Bool = true, taxPercentageOverride: Decimal? = nil, createdAt: Date = Date(), categories: [String] = [], deletedDate: Date? = nil) {
        self.id = id
        self.name = name
        self.amount = amount.roundedMoney()
        self.date = date
        self.showDate = showDate
        self.endDate = endDate
        self.showEndDate = showEndDate
        self.isRecurring = isRecurring
        self.recurringFrequency = recurringFrequency
        self.recurrenceRule = recurrenceRule
        self.attachments = attachments
        self.isTaxable = isTaxable
        self.taxPercentageOverride = taxPercentageOverride
        self.createdAt = createdAt
        self.categories = categories
        self.deletedDate = deletedDate
    }

    /// Effective recurring frequency string — mirrors Expense for RecurringItem protocol conformance.
    var effectiveFrequency: String { recurringFrequency.rawValue }

    /// Resolved recurrence rule: use stored rule or derive from legacy frequency.
    var resolvedRule: RecurrenceRule { recurrenceRule ?? RecurrenceRule(legacy: recurringFrequency) }

    /// Tax rate to use for this income item as an exact Decimal. Falls back to the budget's
    /// default percentage when no override is set. Division by 100 is exact in Decimal.
    /// NOT rounded to 2dp — rates are multipliers, and rounding 11.5% → 0.115 to 0.12 would
    /// corrupt the value. Rounding to cents belongs at the result of multiplication, not the rate.
    func effectiveTaxRate(defaultPercentage: Double) -> Decimal {
        if let override = taxPercentageOverride {
            return override / 100
        }
        return (Decimal(string: String(defaultPercentage)) ?? 0) / 100
    }
}


// MARK: - Income Duplication

nonisolated extension Income {
    /// Returns a copy of this income with a fresh ID and new IDs on all attachments.
    /// Used for single-item duplication and recurring splits, where the copy should
    /// always start out active (never trashed).
    func duplicate() -> Income {
        Income(
            id: UUID(),
            name: name,
            amount: amount,
            date: date,
            showDate: showDate,
            endDate: endDate,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments.map { $0.withNewID() },
            isTaxable: isTaxable,
            taxPercentageOverride: taxPercentageOverride,
            createdAt: createdAt,
            categories: categories
        )
    }

    /// Returns a faithful copy of this income for whole-budget duplication: fresh ID and
    /// attachment IDs, but preserves `deletedDate` so a trashed income stays trashed in the copy.
    func duplicateForBudgetCopy() -> Income {
        Income(
            id: UUID(),
            name: name,
            amount: amount,
            date: date,
            showDate: showDate,
            endDate: endDate,
            showEndDate: showEndDate,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            recurrenceRule: recurrenceRule,
            attachments: attachments.map { $0.withNewID() },
            isTaxable: isTaxable,
            taxPercentageOverride: taxPercentageOverride,
            createdAt: createdAt,
            categories: categories,
            deletedDate: deletedDate
        )
    }
}

// MARK: - Income Codable Implementation
// Custom Codable implementation to handle migration from legacy 'isUntaxable' property
// to the newer 'isTaxable' property while maintaining backward compatibility

extension Income: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, amount, date, showDate, endDate, showEndDate
        case isRecurring, recurringFrequency, recurrenceRule, attachments, isTaxable
        case taxPercentageOverride
        // Legacy key for migrating old data that used inverted logic
        case isUntaxable
        case createdAt
        case categories
        case category // legacy key for backward compatibility
        case deletedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decodeMoney(forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        showDate = try container.decode(Bool.self, forKey: .showDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        showEndDate = try container.decode(Bool.self, forKey: .showEndDate)
        isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
        recurringFrequency = try container.decode(RecurringFrequency.self, forKey: .recurringFrequency)
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []

        // Migration logic: try new property first, then legacy property, then default to taxable
        if let isTaxable = try container.decodeIfPresent(Bool.self, forKey: .isTaxable) {
            self.isTaxable = isTaxable
        } else if let isUntaxable = try container.decodeIfPresent(Bool.self, forKey: .isUntaxable) {
            // Invert the old isUntaxable value to get isTaxable
            self.isTaxable = !isUntaxable
        } else {
            // Default to taxable if neither property exists
            self.isTaxable = true
        }

        taxPercentageOverride = try container.decodeMoneyIfPresent(forKey: .taxPercentageOverride)

        // Backward compatibility: use date if createdAt is missing (for existing data)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? date

        categories = try decodeCategories(from: container, arrayKey: .categories, legacyKey: .category)
        deletedDate = try container.decodeIfPresent(Date.self, forKey: .deletedDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encode(showDate, forKey: .showDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(showEndDate, forKey: .showEndDate)
        try container.encode(isRecurring, forKey: .isRecurring)
        try container.encode(recurringFrequency, forKey: .recurringFrequency)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(isTaxable, forKey: .isTaxable)
        try container.encodeIfPresent(taxPercentageOverride, forKey: .taxPercentageOverride)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(categories, forKey: .categories)
        try container.encodeIfPresent(deletedDate, forKey: .deletedDate)
    }
}

// MARK: - Attachment Type (Shared)
// Categorizes different types of file attachments and provides display metadata

enum AttachmentType: String, Codable {
    case image
    case pdf
    case document
    case other
    
    /// Human-readable name for the attachment type
    var displayName: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF"
        case .document: return "Document"
        case .other: return "File"
        }
    }
    
    /// SF Symbol icon name for the attachment type
    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.fill"
        case .document: return "doc.text.fill"
        case .other: return "doc"
        }
    }
    
    /// Infers the attachment type from a UTType string
    static func fromUTType(_ utType: String) -> AttachmentType {
        if utType.hasPrefix("image") {
            return .image
        } else if utType.contains("pdf") {
            return .pdf
        } else if utType.contains("text") || utType.contains("document") {
            return .document
        } else {
            return .other
        }
    }
}

// MARK: - Attachment Base Protocol

/// Common interface for Attachment and BudgetAttachment.
/// Enables shared utility code (e.g. share sheet preparation) to work with either type.
protocol AttachmentBase: Identifiable {
    var id: UUID { get }
    var data: Data { get }
    var fileName: String { get }
    var fileType: AttachmentType { get }
    var dateAdded: Date { get }
}

// MARK: - Attachment Model
// Represents a file attachment for income or expense entries (e.g., receipts, invoices, pay stubs)

nonisolated struct Attachment: Identifiable, Equatable, Hashable, Codable, AttachmentBase {
    let id: UUID
    var data: Data
    var fileName: String
    var fileType: AttachmentType
    var dateAdded: Date
    
    init(id: UUID = UUID(), data: Data, fileName: String, fileType: AttachmentType, dateAdded: Date = Date()) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.fileType = fileType
        self.dateAdded = dateAdded
    }

    func withNewID() -> Attachment {
        Attachment(id: UUID(), data: data, fileName: fileName, fileType: fileType, dateAdded: dateAdded)
    }
}

// MARK: - Budget Attachment Model
// Represents a file attachment associated with a specific month/year budget period

struct BudgetAttachment: Identifiable, Equatable, Hashable, Codable, AttachmentBase {
    let id: UUID
    var data: Data
    var fileName: String
    var fileType: AttachmentType
    var dateAdded: Date
    var month: Int  // 1-12 representing January through December
    var year: Int   // Full year (e.g., 2026)

    // Soft-delete: set when moved to trash, nil when active
    var deletedDate: Date?

    var daysUntilTrashDeletion: Int? {
        guard let deletedDate else { return nil }
        let daysSinceDeletion = Calendar.current.dateComponents([.day], from: deletedDate, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }

    init(id: UUID = UUID(), data: Data, fileName: String, fileType: AttachmentType, dateAdded: Date = Date(), month: Int, year: Int, deletedDate: Date? = nil) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.fileType = fileType
        self.dateAdded = dateAdded
        self.month = month
        self.year = year
        self.deletedDate = deletedDate
    }

    func withNewID() -> BudgetAttachment {
        BudgetAttachment(id: UUID(), data: data, fileName: fileName, fileType: fileType, dateAdded: dateAdded, month: month, year: year)
    }

    /// Returns a faithful copy of this attachment for whole-budget duplication: fresh ID,
    /// but preserves `deletedDate` so a trashed attachment stays trashed in the copy.
    func duplicateForBudgetCopy() -> BudgetAttachment {
        BudgetAttachment(id: UUID(), data: data, fileName: fileName, fileType: fileType, dateAdded: dateAdded, month: month, year: year, deletedDate: deletedDate)
    }
}

// MARK: - Budget Attachment Codable Implementation
// Custom Codable implementation to handle backward compatibility for legacy data
// that may be missing month/year properties (defaults to current month/year)

extension BudgetAttachment {
    enum CodingKeys: String, CodingKey {
        case id, data, fileName, fileType, dateAdded, month, year, deletedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        data = try container.decode(Data.self, forKey: .data)
        fileName = try container.decode(String.self, forKey: .fileName)
        fileType = try container.decode(AttachmentType.self, forKey: .fileType)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)

        // Backward compatibility: default to current month/year if properties are missing
        let calendar = Calendar.current
        let now = Date()
        month = try container.decodeIfPresent(Int.self, forKey: .month) ?? calendar.component(.month, from: now)
        year = try container.decodeIfPresent(Int.self, forKey: .year) ?? calendar.component(.year, from: now)
        deletedDate = try container.decodeIfPresent(Date.self, forKey: .deletedDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(fileType, forKey: .fileType)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(month, forKey: .month)
        try container.encode(year, forKey: .year)
        try container.encodeIfPresent(deletedDate, forKey: .deletedDate)
    }
}


// MARK: - Reallocation Model
// Represents a budget reallocation between two different month/year periods.
// Each reallocation operation creates two linked entries: one "from" entry (negative)
// in the source month and one "to" entry (positive) in the destination month.
// Titles are generated automatically from the month/year data and are not stored.

nonisolated struct Reallocation: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let linkedId: UUID  // The ID of the paired reallocation entry (links "from" and "to" entries)
    var amount: Decimal
    var fromMonth: Int  // 1-12 representing January through December
    var fromYear: Int
    var toMonth: Int    // 1-12 representing January through December
    var toYear: Int
    var isFromEntry: Bool  // true if this represents the deduction, false if this represents the addition
    var date: Date  // The specific date when this reallocation occurs (includes day, hour, minute)

    // Timestamp when this reallocation was created (for sorting items in same month)
    var createdAt: Date

    // File attachments (receipts, notes, etc.)
    var attachments: [Attachment]

    init(id: UUID = UUID(), linkedId: UUID, amount: Decimal, fromMonth: Int, fromYear: Int, toMonth: Int, toYear: Int, isFromEntry: Bool, date: Date = Date(), createdAt: Date = Date(), attachments: [Attachment] = []) {
        self.id = id
        self.linkedId = linkedId
        self.amount = amount.roundedMoney()
        self.fromMonth = fromMonth
        self.fromYear = fromYear
        self.toMonth = toMonth
        self.toYear = toYear
        self.isFromEntry = isFromEntry
        self.date = date
        self.createdAt = createdAt
        self.attachments = attachments
    }

}

// MARK: - Reallocation Codable Implementation
// Custom Codable implementation to handle backward compatibility for legacy data
// that may be missing the createdAt timestamp or date field, or may have stored title values

nonisolated extension Reallocation {
    enum CodingKeys: String, CodingKey {
        case id, linkedId, title, amount
        case fromMonth, fromYear, toMonth, toYear
        case isFromEntry, date, createdAt
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        linkedId = try container.decode(UUID.self, forKey: .linkedId)
        // Backward compatibility: ignore title if present in old data
        _ = try? container.decode(String.self, forKey: .title)
        amount = try container.decodeMoney(forKey: .amount)
        fromMonth = try container.decode(Int.self, forKey: .fromMonth)
        fromYear = try container.decode(Int.self, forKey: .fromYear)
        toMonth = try container.decode(Int.self, forKey: .toMonth)
        toYear = try container.decode(Int.self, forKey: .toYear)
        isFromEntry = try container.decode(Bool.self, forKey: .isFromEntry)

        // Backward compatibility: use current date if date is missing (for existing data)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()

        // Backward compatibility: use current date if createdAt is missing (for existing data)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        // Backward compatibility: default to empty array for existing data without attachments
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(linkedId, forKey: .linkedId)
        // No longer encode title - it's generated on the fly from month/year data
        try container.encode(amount, forKey: .amount)
        try container.encode(fromMonth, forKey: .fromMonth)
        try container.encode(fromYear, forKey: .fromYear)
        try container.encode(toMonth, forKey: .toMonth)
        try container.encode(toYear, forKey: .toYear)
        try container.encode(isFromEntry, forKey: .isFromEntry)
        try container.encode(date, forKey: .date)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(attachments, forKey: .attachments)
    }
}

// MARK: - Reallocation Duplication

nonisolated extension Reallocation {
    /// Returns a faithful copy of this reallocation for whole-budget duplication: fresh `id`
    /// and `linkedId` (consistently remapped across the "from"/"to" pair via `idMap`, so both
    /// halves of a reallocation still point at each other after the copy) and fresh attachment
    /// IDs. Every other field, including attachments themselves, is preserved.
    func duplicateForBudgetCopy(idMap: inout [UUID: UUID]) -> Reallocation {
        func remapped(_ id: UUID) -> UUID {
            if let existing = idMap[id] { return existing }
            let newId = UUID()
            idMap[id] = newId
            return newId
        }
        return Reallocation(
            id: remapped(id),
            linkedId: remapped(linkedId),
            amount: amount,
            fromMonth: fromMonth,
            fromYear: fromYear,
            toMonth: toMonth,
            toYear: toYear,
            isFromEntry: isFromEntry,
            date: date,
            createdAt: createdAt,
            attachments: attachments.map { $0.withNewID() }
        )
    }
}

// MARK: - Reallocation Signed Amount

nonisolated extension Reallocation {
    /// The net contribution of this reallocation: negative for "from" entries (money leaves),
    /// positive for "to" entries (money arrives).
    var signedAmount: Decimal { isFromEntry ? -amount : amount }
}

// MARK: - Reallocation Array Helpers

nonisolated extension Array where Element == Reallocation {
    /// Filters reallocations that are active in the given year-month (handles both from- and to-entries).
    func activeIn(yearMonth: YearMonth) -> [Reallocation] {
        filter { r in
            r.isFromEntry
                ? r.fromYear == yearMonth.year && r.fromMonth == yearMonth.month
                : r.toYear == yearMonth.year && r.toMonth == yearMonth.month
        }
    }

    /// Filters only incoming (to) reallocations for the given year-month.
    /// - Parameter excluding: Optional set of reallocation IDs to omit (e.g. when editing an existing pair).
    func additionsIn(yearMonth: YearMonth, excluding: Set<UUID> = []) -> [Reallocation] {
        filter { !excluding.contains($0.id) && !$0.isFromEntry && $0.toYear == yearMonth.year && $0.toMonth == yearMonth.month }
    }

    /// Filters only outgoing (from) reallocations for the given year-month.
    /// - Parameter excluding: Optional set of reallocation IDs to omit (e.g. when editing an existing pair).
    func deductionsIn(yearMonth: YearMonth, excluding: Set<UUID> = []) -> [Reallocation] {
        filter { !excluding.contains($0.id) && $0.isFromEntry && $0.fromYear == yearMonth.year && $0.fromMonth == yearMonth.month }
    }
}

// MARK: - Odometer Reading Model
// Represents a single odometer reading for a vehicle. Readings are cumulative per vehicle;
// "miles driven" for a given period is derived elsewhere from the difference between readings
// (see BudgetHelpers.swift), not stored directly on the reading itself.

nonisolated struct OdometerReading: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var vehicle: String
    var odometerValue: Int
    var date: Date
    var categories: [String]
    var attachments: [Attachment]
    var createdAt: Date

    init(id: UUID = UUID(), vehicle: String, odometerValue: Int, date: Date, categories: [String] = [], attachments: [Attachment] = [], createdAt: Date = Date()) {
        self.id = id
        self.vehicle = vehicle
        self.odometerValue = odometerValue
        self.date = date
        self.categories = categories
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

// MARK: - Odometer Reading Duplication

nonisolated extension OdometerReading {
    /// Returns a faithful copy of this reading for whole-budget duplication: fresh ID and
    /// attachment IDs. There is no trash concept for odometer readings, so unlike the other
    /// budget-copy helpers there is no `deletedDate` to preserve.
    func duplicateForBudgetCopy() -> OdometerReading {
        OdometerReading(
            id: UUID(),
            vehicle: vehicle,
            odometerValue: odometerValue,
            date: date,
            categories: categories,
            attachments: attachments.map { $0.withNewID() },
            createdAt: createdAt
        )
    }
}
