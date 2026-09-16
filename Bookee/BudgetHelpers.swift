//
//  BudgetHelpers.swift
//  Bookee
//
//  Shared date, budget, and occurrence helpers used across budget views.
//

import SwiftUI
import SwiftData

// MARK: - Shared Last-Day-Of-Month Helper

nonisolated func isLastDayOfMonth(year: Int, month: Int, day: Int) -> Bool {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))?.isLastDayOfMonth ?? false
}

// MARK: - Reimbursement Category Swap

/// When duplicating an expense as income, swaps "Pending Reimbursement" to "Reimbursed" on the
/// expense and "Reimbursement" on the income — but only if all three categories are visible and
/// "Pending Reimbursement" is selected on the expense. Returns nil if the swap should not apply.
func reimbursementCategorySwap(
    expenseCategories: [String],
    storedCategories: [String],
    hiddenCategories: [String]
) -> (expenseCategories: [String], incomeCategories: [String])? {
    let pending = "Pending Reimbursement"
    let reimbursed = "Reimbursed"
    let reimbursement = "Reimbursement"
    guard expenseCategories.contains(pending),
          storedCategories.contains(pending),
          storedCategories.contains(reimbursed),
          storedCategories.contains(reimbursement),
          !hiddenCategories.contains(pending),
          !hiddenCategories.contains(reimbursed),
          !hiddenCategories.contains(reimbursement) else { return nil }
    var newExpense = expenseCategories.filter { $0 != pending }
    if !newExpense.contains(reimbursed) { newExpense.append(reimbursed) }
    var newIncome = expenseCategories.filter { $0 != pending }
    if !newIncome.contains(reimbursement) { newIncome.append(reimbursement) }
    return (newExpense, newIncome)
}

// MARK: - Shared Expense-to-Income Conversion

/// Creates a non-taxable, non-recurring Income from an Expense (used by payOffExpense in both budget views).
func makeIncomeFromExpense(_ expense: Expense) -> Income {
    Income(
        name: expense.name,
        amount: expense.amount,
        date: expense.date,
        showDate: expense.showDate,
        isRecurring: false,
        recurringFrequency: .monthly,
        isTaxable: false,
        categories: expense.categories
    )
}

// MARK: - Generic Recurring-Item Deletion

/// Applies a deletion scope to a recurring item, splitting or removing as needed.
/// Works for any `RecurringItem` conforming type (Expense, Income).
/// Non-effectively-recurring items are deleted immediately without consulting the scope.
func applyRecurringItemDeletion<T: RecurringItem>(
    item: T,
    items: inout [T],
    pendingScope: inout RecurringScope?
) {
    guard item.isEffectivelyRecurring else {
        items.removeAll { $0.id == item.id }
        return
    }
    guard let scope = pendingScope else {
        items.removeAll { $0.id == item.id }
        return
    }
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let calendar = Calendar.current
    let original = items[index]
    let occurrenceDate = calendar.startOfDay(for: item.date)
    guard let normalizedStart = calendar.date(
        from: calendar.dateComponents([.year, .month, .day], from: original.date)) else {
        items.removeAll { $0.id == item.id }
        pendingScope = nil
        return
    }
    let frequency = original.effectiveFrequency
    let rule = original.resolvedRule
    switch scope {
    case .all:
        items.removeAll { $0.id == item.id }
    case .currentAndFuture:
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: occurrenceDate) else {
            items.removeAll { $0.id == item.id }
            pendingScope = nil
            return
        }
        if occurrenceDate == normalizedStart {
            items.removeAll { $0.id == item.id }
        } else {
            var updated = original
            updated.endDate = dayBefore
            updated.showEndDate = true
            items[index] = updated
        }
    case .currentOnly:
        let nextOcc = findNextOccurrence(after: occurrenceDate, startDate: normalizedStart, frequency: frequency, rule: rule)
        if occurrenceDate == normalizedStart {
            if let end = original.endDate, nextOcc > end {
                items.removeAll { $0.id == item.id }
            } else {
                var updated = original
                updated.date = nextOcc
                items[index] = updated
            }
        } else {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: occurrenceDate) else {
                items.removeAll { $0.id == item.id }
                pendingScope = nil
                return
            }
            var before = original
            before.endDate = dayBefore
            before.showEndDate = true
            items[index] = before
            let shouldCreateAfter = original.endDate.map { nextOcc <= $0 } ?? true
            if shouldCreateAfter {
                var after = original.duplicate()
                after.date = nextOcc
                items.append(after)
            }
        }
    }
    pendingScope = nil
}

// MARK: - Recurring Occurrence Utilities

/// Finds the next occurrence date after `date` for an item with the given start date and
/// recurring frequency raw-value string (e.g. "Monthly").
func findNextOccurrence(after date: Date, startDate: Date, frequency: String, rule: RecurrenceRule? = nil) -> Date {
    if let rule = rule, let next = rule.nextOccurrence(after: date, startDate: startDate) { return next }
    let calendar = Calendar.current
    switch frequency {
    case "Daily":    return calendar.date(byAdding: .day,        value: 1,  to: date) ?? date
    case "Weekly":   return calendar.date(byAdding: .day,        value: 7,  to: date) ?? date
    case "Bi-weekly":return calendar.date(byAdding: .day,        value: 14, to: date) ?? date
    case "Monthly", "Quarterly", "Yearly":
        let startDay = calendar.component(.day, from: startDate)
        let monthsToAdd: Int
        switch frequency {
        case "Quarterly": monthsToAdd = 3
        case "Yearly":    monthsToAdd = 12
        default:          monthsToAdd = 1
        }
        let isLastDay = startDate.isLastDayOfMonth
        var current = date
        while true {
            guard let next = calendar.date(byAdding: .month, value: monthsToAdd, to: current) else { return date }
            let yr = calendar.component(.year,  from: next)
            let mo = calendar.component(.month, from: next)
            let targetDay: Int
            if let first = calendar.firstOfMonth(month: mo, year: yr),
               let range = calendar.range(of: .day, in: .month, for: first) {
                targetDay = isLastDay ? range.count : min(startDay, range.count)
            } else {
                targetDay = startDay
            }
            if let result = calendar.date(from: DateComponents(year: yr, month: mo, day: targetDay)) {
                return result
            }
            current = next
        }
    default:
        return calendar.date(byAdding: .month, value: 1, to: date) ?? date
    }
}

// MARK: - Item-in-Month Check

/// Returns true when an item (recurring or one-time) is active during the given target month/year.
func isItemInSelectedMonth(date: Date, endDate: Date?, isRecurring: Bool, targetMonth: Int, targetYear: Int) -> Bool {
    let calendar = Calendar.current
    let itemStartYear  = calendar.component(.year,  from: date)
    let itemStartMonth = calendar.component(.month, from: date)
    if !isRecurring {
        return itemStartYear == targetYear && itemStartMonth == targetMonth
    }
    if itemStartYear > targetYear || (itemStartYear == targetYear && itemStartMonth > targetMonth) {
        return false
    }
    if let end = endDate {
        let endYear  = calendar.component(.year,  from: end)
        let endMonth = calendar.component(.month, from: end)
        if endYear < targetYear || (endYear == targetYear && endMonth < targetMonth) {
            return false
        }
    }
    return true
}

// MARK: - Shared Year-Month Type

/// Represents a specific year-month combination for grouping budget data.
/// Used by both BudgetPageView and IncomePageView.
nonisolated struct YearMonth: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    let month: Int

    var id: String { "\(year)-\(month)" }
    var displayName: String { monthDisplayName(month) }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}

// MARK: - Shared Item Sort Helper

/// Sorts top-level budget/income `Item`s the same way the home screen does, so Search's
/// "Budgets" section and per-budget result sections list in a familiar order.
func sortedItems(_ items: [Item], by sortOrder: SortOrder) -> [Item] {
    switch sortOrder {
    case .manual:
        return items.sorted { $0.manualSortOrder < $1.manualSortOrder }
    case .dateAdded:
        return items.sorted { $0.timestamp > $1.timestamp }
    case .dateOpened:
        return items.sorted { $0.lastOpenedDate > $1.lastOpenedDate }
    }
}

// MARK: - Shared Item-in-Year Helper

/// Returns true when a budget item (defined by its start date and optional end date) is relevant
/// to the given `selectedYear`. Does not require the caller to capture `selectedYear` in a closure.
func isItemInYear(_ selectedYear: Int, startDate: Date, endDate: Date?) -> Bool {
    let calendar = Calendar.current
    let itemStartYear = calendar.component(.year, from: startDate)
    guard itemStartYear <= selectedYear else { return false }
    if let end = endDate {
        let endYear = calendar.component(.year, from: end)
        return selectedYear <= endYear
    }
    return true
}

// MARK: - Shared Recurring Day Check

/// Determines if a recurring item should be displayed on a specific day.
/// Validates that the item has started, hasn't ended, and matches the recurrence pattern.
/// Handles special cases like last day of month and varying month lengths.
nonisolated func shouldRecurringItemAppearOnDay(startDate: Date, endDate: Date?, frequency: String, day: Int, month: Int, year: Int, rule: RecurrenceRule? = nil) -> Bool {
    let calendar = Calendar.current
    let startMonth = calendar.component(.month, from: startDate)
    let startDay = calendar.component(.day, from: startDate)
    guard let checkDate = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
    guard let normalizedStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: startDate)),
          let normalizedCheck = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: checkDate)) else { return false }
    if normalizedCheck < normalizedStart { return false }
    if let end = endDate {
        guard let normalizedEnd = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: end)) else { return false }
        if normalizedCheck > normalizedEnd { return false }
    }
    if let rule = rule { return rule.occurs(onDay: checkDate, startDate: startDate) }
    switch frequency {
    case "Daily":
        return true
    case "Weekly", "Bi-weekly":
        let startWeekday = calendar.component(.weekday, from: startDate)
        let checkWeekday = calendar.component(.weekday, from: checkDate)
        guard startWeekday == checkWeekday else { return false }
        let daysDifference = calendar.dateComponents([.day], from: normalizedStart, to: normalizedCheck).day ?? 0
        return daysDifference % (frequency == "Bi-weekly" ? 14 : 7) == 0
    case "Monthly", "Quarterly":
        let isStartDateLastDayOfMonth = startDate.isLastDayOfMonth
        if isStartDateLastDayOfMonth {
            guard isLastDayOfMonth(year: year, month: month, day: day) else { return false }
        } else {
            let daysInCheckMonth = calendar.range(of: .day, in: .month, for: checkDate)?.count ?? 30
            guard day == min(startDay, daysInCheckMonth) else { return false }
        }
        let components = calendar.dateComponents([.year, .month], from: normalizedStart, to: normalizedCheck)
        let totalMonths = (components.year ?? 0) * 12 + (components.month ?? 0)
        return frequency == "Quarterly" ? totalMonths % 3 == 0 : totalMonths >= 0
    case "Yearly":
        let isStartDateLastDayOfMonth = startDate.isLastDayOfMonth
        if isStartDateLastDayOfMonth {
            return startMonth == month && isLastDayOfMonth(year: year, month: month, day: day)
        } else {
            guard startMonth == month else { return false }
            let daysInCheckMonth = calendar.range(of: .day, in: .month, for: checkDate)?.count ?? 30
            return day == min(startDay, daysInCheckMonth)
        }
    default:
        return false
    }
}

// MARK: - Shared Month-Active Check

/// Determines if a recurring item is active during a target month/year.
/// Handles all frequencies, including weekly/bi-weekly day-of-week matching.
nonisolated func isItemActiveInMonth(date: Date, endDate: Date?, targetMonth: Int, targetYear: Int, frequency: String? = nil, rule: RecurrenceRule? = nil) -> Bool {
    let calendar = Calendar.current
    let itemStartYear = calendar.component(.year, from: date)
    let itemStartMonth = calendar.component(.month, from: date)
    let hasStarted: Bool
    if itemStartYear < targetYear { hasStarted = true }
    else if itemStartYear == targetYear { hasStarted = itemStartMonth <= targetMonth }
    else { hasStarted = false }
    guard hasStarted else { return false }
    if let end = endDate {
        let endYear = calendar.component(.year, from: end)
        let endMonth = calendar.component(.month, from: end)
        let hasEnded: Bool
        if endYear < targetYear { hasEnded = true }
        else if endYear == targetYear { hasEnded = endMonth < targetMonth }
        else { hasEnded = false }
        guard !hasEnded else { return false }
    }
    if let rule = rule {
        let ivl = max(1, rule.interval)
        switch rule.unit {
        case .day: return true
        case .week:
            guard let firstDayOfMonth = calendar.firstOfMonth(month: targetMonth, year: targetYear),
                  let daysInMonth = calendar.range(of: .day, in: .month, for: firstDayOfMonth)?.count else { return false }
            for day in 1...daysInMonth {
                if shouldRecurringItemAppearOnDay(startDate: date, endDate: endDate, frequency: "", day: day, month: targetMonth, year: targetYear, rule: rule) { return true }
            }
            return false
        case .month:
            guard let targetFirstDay = calendar.firstOfMonth(month: targetMonth, year: targetYear) else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date, to: targetFirstDay)
            let totalMonths = (comps.year ?? 0) * 12 + (comps.month ?? 0)
            guard totalMonths % ivl == 0 else { return false }
            switch rule.monthlyPattern {
            case .dayOfMonth: return true  // always appears at least once per qualifying month
            case .nthWeekday:
                guard let daysInMonth = calendar.range(of: .day, in: .month, for: targetFirstDay)?.count else { return false }
                for day in 1...daysInMonth {
                    if shouldRecurringItemAppearOnDay(startDate: date, endDate: endDate, frequency: "", day: day, month: targetMonth, year: targetYear, rule: rule) { return true }
                }
                return false
            }
        case .year:
            let startMonth = calendar.component(.month, from: date)
            let startYear = calendar.component(.year, from: date)
            guard startMonth == targetMonth else { return false }
            return (targetYear - startYear) % ivl == 0
        }
    }
    guard let freq = frequency else { return true }
    switch freq {
    case "Daily": return true
    case "Weekly", "Bi-weekly":
        guard let firstDayOfMonth = calendar.firstOfMonth(month: targetMonth, year: targetYear),
              let daysInMonth = calendar.range(of: .day, in: .month, for: firstDayOfMonth)?.count else { return false }
        for day in 1...daysInMonth {
            if shouldRecurringItemAppearOnDay(startDate: date, endDate: endDate, frequency: freq, day: day, month: targetMonth, year: targetYear) { return true }
        }
        return false
    case "Monthly": return true
    case "Quarterly":
        let components = calendar.dateComponents([.year, .month], from: date, to: calendar.firstOfMonth(month: targetMonth, year: targetYear)!)
        return ((components.year ?? 0) * 12 + (components.month ?? 0)) % 3 == 0
    case "Yearly": return itemStartMonth == targetMonth
    default: return true
    }
}

// MARK: - Shared Occurrence Count Helper

/// Counts how many times a recurring item occurs within a specific month.
/// Iterates every day of the month using `shouldRecurringItemAppearOnDay` for accuracy.
/// Returns 0 when the item has no occurrences in the given month.
func countOccurrencesInMonth(startDate: Date, endDate: Date?, frequency: String, month: Int, year: Int, rule: RecurrenceRule? = nil) -> Int {
    let calendar = Calendar.current
    guard let firstDayOfMonth = calendar.firstOfMonth(month: month, year: year),
          let daysInMonth = calendar.range(of: .day, in: .month, for: firstDayOfMonth)?.count else {
        return 0
    }
    var count = 0
    for day in 1...daysInMonth {
        if shouldRecurringItemAppearOnDay(startDate: startDate, endDate: endDate,
                                          frequency: frequency, day: day,
                                          month: month, year: year, rule: rule) {
            count += 1
        }
    }
    return count
}

// MARK: - Category Counts Helper

/// Returns a count of transaction occurrences per category for the given month,
/// expanding recurring items into their individual occurrences.
func buildCategoryCounts(for item: Item, month: Int, year: Int) -> [String: Int] {
    let data = item.decodeBudgetDataExcludingAttachments()
    return buildCategoryCounts(expenses: data?.expenses ?? [], incomes: data?.incomes ?? [],
                               odometerReadings: data?.odometerReadings ?? [], month: month, year: year)
}

/// Core implementation that works purely from pre-decoded value types — safe to call off the main actor.
func buildCategoryCounts(expenses: [Expense], incomes: [Income], odometerReadings: [OdometerReading] = [], month: Int, year: Int) -> [String: Int] {
    var counts: [String: Int] = [:]
    let sentinel = SettingsDefault.uncategorizedSentinel

    func tally(_ cats: [String], occurrences: Int) {
        let effective = cats.filter { $0 != sentinel }
        if effective.isEmpty {
            counts[sentinel, default: 0] += occurrences
        } else {
            for cat in effective { counts[cat, default: 0] += occurrences }
        }
    }

    for expense in expenses where expense.deletedDate == nil {
        let isRecurring = expense.isRecurring || expense.isMonthlyPaymentPlan
        if isRecurring {
            let n = countOccurrencesInMonth(startDate: expense.date, endDate: expense.endDate,
                                            frequency: expense.effectiveFrequency,
                                            month: month, year: year, rule: expense.resolvedRule)
            if n > 0 { tally(expense.categories, occurrences: n) }
        } else if isItemInSelectedMonth(date: expense.date, endDate: expense.endDate,
                                        isRecurring: false, targetMonth: month, targetYear: year) {
            tally(expense.categories, occurrences: 1)
        }
    }

    for income in incomes where income.deletedDate == nil {
        if income.isRecurring {
            let n = countOccurrencesInMonth(startDate: income.date, endDate: income.endDate,
                                            frequency: income.recurringFrequency.rawValue,
                                            month: month, year: year, rule: income.resolvedRule)
            if n > 0 { tally(income.categories, occurrences: n) }
        } else if isItemInSelectedMonth(date: income.date, endDate: income.endDate,
                                        isRecurring: false, targetMonth: month, targetYear: year) {
            tally(income.categories, occurrences: 1)
        }
    }

    for reading in odometerReadings where reading.date.year == year && reading.date.month == month {
        tally(reading.categories, occurrences: 1)
    }

    return counts
}

// MARK: - Type Counts Helper

func buildTypeCounts(for item: Item, month: Int, year: Int) -> [TransactionFilter: Int] {
    let data = item.decodeBudgetDataExcludingAttachments()
    let expenses = (data?.expenses ?? []).filter { $0.deletedDate == nil }
    let incomes = (data?.incomes ?? []).filter { $0.deletedDate == nil }
    let activeReallocations = (data?.reallocations ?? []).activeIn(yearMonth: YearMonth(year: year, month: month))

    var counts: [TransactionFilter: Int] = [:]

    for income in incomes {
        let n: Int
        if income.isRecurring {
            n = countOccurrencesInMonth(startDate: income.date, endDate: income.endDate,
                                        frequency: income.recurringFrequency.rawValue,
                                        month: month, year: year, rule: income.resolvedRule)
        } else if isItemInSelectedMonth(date: income.date, endDate: income.endDate,
                                        isRecurring: false, targetMonth: month, targetYear: year) {
            n = 1
        } else {
            n = 0
        }
        guard n > 0 else { continue }
        counts[.income, default: 0] += n
        if income.isRecurring { counts[.recurringIncome, default: 0] += n }
        else { counts[.oneTimeIncome, default: 0] += n }
        if income.isTaxable { counts[.taxableIncome, default: 0] += n }
        else { counts[.otherIncome, default: 0] += n }
    }

    for expense in expenses {
        let isRecurringOrPlan = expense.isRecurring || expense.isMonthlyPaymentPlan
        let n: Int
        if isRecurringOrPlan {
            n = countOccurrencesInMonth(startDate: expense.date, endDate: expense.endDate,
                                        frequency: expense.effectiveFrequency,
                                        month: month, year: year, rule: expense.resolvedRule)
        } else if isItemInSelectedMonth(date: expense.date, endDate: expense.endDate,
                                        isRecurring: false, targetMonth: month, targetYear: year) {
            n = 1
        } else {
            n = 0
        }
        guard n > 0 else { continue }
        counts[.expenses, default: 0] += n
        if expense.isMonthlyPaymentPlan { counts[.paymentPlans, default: 0] += n }
        else if expense.isRecurring { counts[.recurringExpenses, default: 0] += n }
        else { counts[.oneTimeExpense, default: 0] += n }
    }

    counts[.reallocations] = activeReallocations.count
    counts[.positiveReallocation] = activeReallocations.filter { !$0.isFromEntry }.count
    counts[.negativeReallocation] = activeReallocations.filter { $0.isFromEntry }.count

    return counts
}

// MARK: - Category Rename Helper

/// Renames `old` to `new` in every item's `categories` array. Generic over a WritableKeyPath
/// so the same logic covers both Expense and Income without duplication.
func renamingCategory<T>(_ old: String, to new: String, in items: [T], keyPath: WritableKeyPath<T, [String]>) -> [T] {
    items.map { var x = $0; x[keyPath: keyPath] = x[keyPath: keyPath].map { $0 == old ? new : $0 }; return x }
}
func renamingCategory(_ old: String, to new: String, in items: [Expense]) -> [Expense] {
    renamingCategory(old, to: new, in: items, keyPath: \.categories)
}
func renamingCategory(_ old: String, to new: String, in items: [Income]) -> [Income] {
    renamingCategory(old, to: new, in: items, keyPath: \.categories)
}

// MARK: - Category Rename Persistence

/// Renames `old` to `new` in the stored expenses/incomes data of every SwiftData Item.
/// Shared by CategoryPickerView and FilterOptionsSheet so the byte-identical implementations
/// live in one place. Uses direct JSON decode/encode to update only the relevant fields.
func updateItemsForRenamedCategory(from old: String, to new: String, modelContext: ModelContext) {
    let fetchDescriptor = FetchDescriptor<Item>()
    guard let items = try? modelContext.fetch(fetchDescriptor) else { return }
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    for item in items {
        if let data = item.expensesData,
           let expenses = try? decoder.decode([Expense].self, from: data) {
            let renamed = renamingCategory(old, to: new, in: expenses)
            if renamed != expenses, let encoded = try? encoder.encode(renamed) { item.expensesData = encoded }
        }
        if let data = item.incomesData,
           let incomes = try? decoder.decode([Income].self, from: data) {
            let renamed = renamingCategory(old, to: new, in: incomes)
            if renamed != incomes, let encoded = try? encoder.encode(renamed) { item.incomesData = encoded }
        }
        if let data = item.odometerReadingsData,
           let odometerReadings = try? decoder.decode([OdometerReading].self, from: data) {
            let renamed = odometerReadings.map { var x = $0; x.categories = x.categories.map { $0 == old ? new : $0 }; return x }
            if renamed != odometerReadings, let encoded = try? encoder.encode(renamed) { item.odometerReadingsData = encoded }
        }
    }
}

// MARK: - Category Delete Persistence

/// Removes `category` from every expense and income across all SwiftData Items.
func updateItemsForDeletedCategory(_ category: String, modelContext: ModelContext) {
    let fetchDescriptor = FetchDescriptor<Item>()
    guard let items = try? modelContext.fetch(fetchDescriptor) else { return }
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    for item in items {
        if let data = item.expensesData,
           let expenses = try? decoder.decode([Expense].self, from: data) {
            let updated = expenses.map { var x = $0; x.categories.removeAll { $0 == category }; return x }
            if updated != expenses, let encoded = try? encoder.encode(updated) { item.expensesData = encoded }
        }
        if let data = item.incomesData,
           let incomes = try? decoder.decode([Income].self, from: data) {
            let updated = incomes.map { var x = $0; x.categories.removeAll { $0 == category }; return x }
            if updated != incomes, let encoded = try? encoder.encode(updated) { item.incomesData = encoded }
        }
        if let data = item.odometerReadingsData,
           let odometerReadings = try? decoder.decode([OdometerReading].self, from: data) {
            let updated = odometerReadings.map { var x = $0; x.categories.removeAll { $0 == category }; return x }
            if updated != odometerReadings, let encoded = try? encoder.encode(updated) { item.odometerReadingsData = encoded }
        }
    }
}

// MARK: - Budget Data Persistence Helper

/// Encodes all four budget arrays into `item`'s external storage and saves the SwiftData context.
/// Shared by BudgetPageView and MonthDetailsPageView so the body exists in one place.
func saveBudgetData(
    to item: Item,
    expenses: [Expense], incomes: [Income],
    attachments: [BudgetAttachment], reallocations: [Reallocation],
    odometerReadings: [OdometerReading]
) {
    item.lastModifiedDate = Date()
    do {
        try item.encodeBudgetData(expenses: expenses, incomes: incomes,
                                   attachments: attachments, reallocations: reallocations,
                                   odometerReadings: odometerReadings)
        print("💾 Saved \(expenses.count) expense(s), \(incomes.count) income(s), \(attachments.count) attachment(s), \(reallocations.count) reallocation(s), and \(odometerReadings.count) odometer reading(s)")
        try item.modelContext?.save()
        print("✅ SwiftData context saved")
    } catch {
        print("❌ Error saving data: \(error)")
    }
}

// MARK: - Available Funds Computation

/// Computes available surplus funds in a given "from" month for reallocation.
/// Correctly counts multiple occurrences of weekly/bi-weekly recurring items per month,
/// and uses frequency-aware active checks (so quarterly items only count in their actual months).
/// Pass `excludingIDs` when editing an existing pair so the current entries are not double-counted.
func computeAvailableFundsInFromMonth(
    incomes: [Income], expenses: [Expense], reallocations: [Reallocation],
    fromMonth: Int, fromYear: Int, toMonth: Int, toYear: Int,
    item: Item, excludingIDs: Set<UUID> = []
) -> Decimal {
    let isMovingBackwards = (fromYear > toYear) || (fromYear == toYear && fromMonth > toMonth)

    let activeIncomes = incomes.filter { $0.deletedDate == nil }
    let incomeAmounts: [(income: Income, amount: Decimal)] = activeIncomes.compactMap { income in
        guard let amount = effectiveMonthlyAmount(for: income, month: fromMonth, year: fromYear) else { return nil }
        return (income, amount)
    }
    let totalIncome = incomeAmounts.map { $0.amount }.sumMoney()
    let totalTax: Decimal = item.isTaxActive
        ? TaxDistributionHelper.distributedTaxAmounts(for: incomeAmounts, defaultPercentage: item.taxSavingsPercentage).values.sumMoney()
        : 0

    let existingReallocationsIn  = reallocations.additionsIn(yearMonth: YearMonth(year: fromYear, month: fromMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()
    let existingReallocationsOut = reallocations.deductionsIn(yearMonth: YearMonth(year: fromYear, month: fromMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()

    let applyTax: (Decimal) -> Decimal = { available in
        guard item.isTaxActive else {
            return max(0, available.roundedMoney())
        }
        return max(0, roundMoney(available - totalTax))
    }

    // When pulling from a later month into a past month, show the same income
    // total as the budget page (gross income + positive reallocations, minus taxes).
    // Negative reallocations are a separate deduction on the budget page and are
    // not subtracted here.
    if isMovingBackwards {
        let available = roundMoney(totalIncome + existingReallocationsIn)
        return applyTax(available)
    }

    let activeExpenses = expenses.filter { $0.deletedDate == nil }
    let totalExpenses = activeExpenses.compactMap { effectiveMonthlyAmount(for: $0, month: fromMonth, year: fromYear) }.sumMoney()
    let available = roundMoney(roundMoney(totalIncome + existingReallocationsIn) - roundMoney(totalExpenses + existingReallocationsOut))
    return applyTax(available)
}

// MARK: - Year-Month Collection Helper

/// Returns all 12 YearMonth values for the given year (January through December).
func allYearMonths(for year: Int) -> [YearMonth] {
    (1...12).map { YearMonth(year: year, month: $0) }
}

// MARK: - Generic Item Grouping by Year-Month

/// Groups recurring and one-time items by year-month for the given year.
/// Recurring items (those where `isEffectivelyRecurring` is true) appear in every month they are active.
/// One-time items appear only in their specific month.
func groupByYearMonth<T: RecurringItem>(_ items: [T], selectedYear: Int) -> [YearMonth: [T]] {
    var grouped: [YearMonth: [T]] = [:]
    for item in items {
        if isItemInYear(selectedYear, startDate: item.date, endDate: item.endDate) {
            if item.isEffectivelyRecurring {
                for monthNum in 1...12 {
                    let ym = YearMonth(year: selectedYear, month: monthNum)
                    if isItemActiveInMonth(date: item.date, endDate: item.endDate,
                                           targetMonth: monthNum, targetYear: selectedYear,
                                           frequency: item.effectiveFrequency,
                                           rule: item.resolvedRule) {
                        grouped[ym, default: []].append(item)
                    }
                }
            } else if item.date.year == selectedYear {
                let ym = YearMonth(year: item.date.year, month: item.date.month)
                grouped[ym, default: []].append(item)
            }
        }
    }
    return grouped.mapValues { $0.sorted { $0.date == $1.date ? $0.createdAt < $1.createdAt : $0.date < $1.date } }
}

// MARK: - Effective Monthly Amount

/// Returns the effective amount a recurring or one-time item contributes in a specific month/year.
/// For recurring items: returns occurrences × amount (nil if no occurrences that month).
/// For one-time items: returns the item's amount if its date falls in the target month, else nil.
/// Generic over any RecurringItem so it works for both Income and Expense.
func effectiveMonthlyAmount<T: RecurringItem>(for item: T, month: Int, year: Int) -> Decimal? {
    if item.isEffectivelyRecurring {
        guard isItemActiveInMonth(date: item.date, endDate: item.endDate,
                                  targetMonth: month, targetYear: year,
                                  frequency: item.effectiveFrequency,
                                  rule: item.resolvedRule) else { return nil }
        let occ = countOccurrencesInMonth(startDate: item.date, endDate: item.endDate,
                                          frequency: item.effectiveFrequency,
                                          month: month, year: year,
                                          rule: item.resolvedRule)
        guard occ > 0 else { return nil }
        return roundMoney(item.amount * Decimal(occ))
    } else {
        guard item.date.year == year && item.date.month == month else { return nil }
        return item.amount
    }
}

// MARK: - Pre-computed Month Data

/// Holds the expanded income/expense arrays and per-day indices for a single month,
/// pre-computed by BudgetPageView and passed into MonthPageView so its body never
/// runs expensive day-scan loops during a swipe.
struct MonthExpandedData {
    let expandedIncomes: [Income]
    let expandedExpenses: [Expense]
    /// Day-number → income occurrences. O(1) lookup for calendar dots and day filters.
    let incomesByDay: [Int: [Income]]
    /// Day-number → expense occurrences. O(1) lookup for calendar dots and day filters.
    let expensesByDay: [Int: [Expense]]
    /// Day-number → reallocation occurrences. O(1) lookup replaces per-cell O(n) filter.
    let reallocationsByDay: [Int: [Reallocation]]
    /// Reallocations active in this month (both "from" and "to" entries).
    let activeReallocations: [Reallocation]
    /// Reallocations that add funds to this month ("to" entries).
    let positiveReallocations: [Reallocation]
    /// Reallocations that remove funds from this month ("from" entries).
    let negativeReallocations: [Reallocation]
    /// All transactions (income + expense + reallocation) pre-sorted by date then createdAt.
    /// Used when no day filter is active; type/category filtering is applied in body.
    let sortedBaseTransactions: [TransactionItem]
    /// Calendar grid pre-built with the item's week-start-day preference. Each inner array
    /// is one week row; nil entries are padding cells outside the current month.
    let calendarWeeks: [[Int?]]
    /// Pre-computed display dates for expanded expenses. Key = TransactionItem.id string
    /// ("\(expense.id.uuidString)-\(expense.date.timeIntervalSince1970)"). Eliminates
    /// multiple Calendar API calls per expense row from the render path.
    let expenseDisplayDates: [String: Date]
    /// Pre-flattened calendar day grid. Avoids repeated flatMap + enumerated in body.
    let flatCalendarDays: [(offset: Int, day: Int?)]

    // MARK: Precomputed header totals (always full-month, independent of live filters)

    /// Sum of all expanded income amounts, regardless of taxability.
    let summaryIncomeTotal: Decimal
    /// Taxable income total; 0 when tax savings is disabled.
    let taxableIncomeTotal: Decimal
    /// Untaxable income total; equals the full income total when tax savings is disabled.
    let untaxableIncomeTotal: Decimal
    /// Sum of all expanded expense amounts.
    let expenseTotal: Decimal
    /// Per-income distributed tax amounts (largest-remainder), keyed by income UUID.
    /// Empty when tax savings is disabled.
    let distributedTaxes: [UUID: Decimal]
    /// Sum of `distributedTaxes`; gated on `isTaxSavingsEnabled` only.
    let summaryTaxTotal: Decimal
    /// Sum of `distributedTaxes`; gated on `isTaxActive` (enabled AND positive percentage).
    let taxSavingsTotal: Decimal
    /// Sum of incoming ("to") reallocation amounts.
    let reallocationInTotal: Decimal
    /// Sum of outgoing ("from") reallocation amounts.
    let reallocationOutTotal: Decimal
    /// Expenses adjusted for net reallocations.
    let headerEffectiveExpenses: Decimal
    /// "Total Excess"/"Total Needed" header value.
    let headerRemaining: Decimal
    let headerBreakEven: Decimal
    let headerIncomeNeeded: Decimal
    /// Active reallocations sorted by createdAt then id, for stable list display.
    let sortedActiveReallocations: [Reallocation]
    /// Odometer readings dated within this month, sorted by date then createdAt.
    let activeOdometerReadings: [OdometerReading]
    /// Per-vehicle miles driven this month: sum of each reading dated in this month minus the
    /// reading immediately before it. A vehicle's very first reading ever contributes 0 (no
    /// predecessor to diff against) rather than its raw odometer value.
    let milesDrivenByVehicle: [String: Int]
    /// Per-reading miles driven: each reading's own delta from the reading immediately before it
    /// (chronologically, same vehicle). A vehicle's very first reading ever has no entry here (no
    /// predecessor to diff against), so callers should default to 0.
    let milesDrivenByReadingID: [UUID: Int]

    static let empty = MonthExpandedData(
        expandedIncomes: [], expandedExpenses: [],
        incomesByDay: [:], expensesByDay: [:],
        reallocationsByDay: [:],
        activeReallocations: [], positiveReallocations: [], negativeReallocations: [],
        sortedBaseTransactions: [],
        calendarWeeks: [],
        expenseDisplayDates: [:],
        flatCalendarDays: [],
        summaryIncomeTotal: 0, taxableIncomeTotal: 0, untaxableIncomeTotal: 0,
        expenseTotal: 0, distributedTaxes: [:], summaryTaxTotal: 0, taxSavingsTotal: 0,
        reallocationInTotal: 0, reallocationOutTotal: 0,
        headerEffectiveExpenses: 0, headerRemaining: 0, headerBreakEven: 0, headerIncomeNeeded: 0,
        sortedActiveReallocations: [],
        activeOdometerReadings: [], milesDrivenByVehicle: [:], milesDrivenByReadingID: [:]
    )
}

// MARK: - Tax Rate / Active Helpers

/// Tax rate as an exact base-10 Decimal (e.g. 11.5% → 0.115 exactly). Mirrors `Item.taxRate` —
/// kept as a free function so `buildMonthData` (called off the main actor) and `Item` share
/// one source of truth.
nonisolated func taxRateDecimal(fromPercentage percentage: Double) -> Decimal {
    (Decimal(string: String(percentage)) ?? 0) / 100
}

/// True when tax savings is both enabled and has a positive percentage. Mirrors `Item.isTaxActive`.
/// Named distinctly from `Item.isTaxActive` to avoid any ambiguity at call sites.
nonisolated func isTaxSavingsActive(isTaxSavingsEnabled: Bool, taxSavingsPercentage: Double) -> Bool {
    isTaxSavingsEnabled && taxSavingsPercentage.isEffectivelyPositive
}

// MARK: - Header Totals Computation (shared by buildMonthData and live-filtered summary totals)

/// Header totals derived from a set of incomes/expenses/reallocations — income/tax split,
/// expense sum, reallocation in/out, and the Total Excess/Needed figures. Field names mirror
/// the matching totals on `MonthExpandedData`.
struct MonthHeaderTotals {
    let incomeTotal: Decimal
    let taxableIncomeTotal: Decimal
    let untaxableIncomeTotal: Decimal
    let expenseTotal: Decimal
    let distributedTaxes: [UUID: Decimal]
    let taxTotal: Decimal
    let taxSavingsTotal: Decimal
    let reallocationInTotal: Decimal
    let reallocationOutTotal: Decimal
    let effectiveExpenses: Decimal
    let remaining: Decimal
    let breakEven: Decimal
    let incomeNeeded: Decimal
}

/// Computes the calendar summary's header totals for an arbitrary set of already-expanded
/// incomes/expenses and already-scoped reallocations. Used by `buildMonthData` for the full,
/// unfiltered month, and directly by MonthPageView for the live-filtered subsets shown in the
/// summary rows when a type/category filter or day selection is active — so both stay byte-for-byte
/// consistent with each other.
nonisolated func computeHeaderTotals(incomes: [Income], expenses: [Expense], reallocations: [Reallocation],
                                      isTaxSavingsEnabled: Bool, taxSavingsPercentage: Double) -> MonthHeaderTotals {
    let taxActive = isTaxSavingsActive(isTaxSavingsEnabled: isTaxSavingsEnabled, taxSavingsPercentage: taxSavingsPercentage)
    let taxRate = taxRateDecimal(fromPercentage: taxSavingsPercentage)

    let taxableIncome: Decimal = isTaxSavingsEnabled ? incomes.filter { $0.isTaxable }.map { $0.amount }.sumMoney() : 0
    let untaxableIncome: Decimal = isTaxSavingsEnabled
        ? incomes.filter { !$0.isTaxable }.map { $0.amount }.sumMoney()
        : incomes.map { $0.amount }.sumMoney()
    let expenseSum = expenses.map { $0.amount }.sumMoney()

    let distributedTaxes: [UUID: Decimal] = isTaxSavingsEnabled
        ? TaxDistributionHelper.distributedTaxAmounts(
            for: incomes.map { (income: $0, amount: $0.amount) },
            defaultPercentage: taxSavingsPercentage)
        : [:]
    let summaryTax: Decimal = isTaxSavingsEnabled ? distributedTaxes.values.sumMoney() : 0
    let taxSavings: Decimal = taxActive ? distributedTaxes.values.sumMoney() : 0

    let reallocIn = reallocations.filter { !$0.isFromEntry }.map { $0.amount }.sumMoney()
    let reallocOut = reallocations.filter { $0.isFromEntry }.map { $0.amount }.sumMoney()

    let reallocated = reallocations.map { $0.signedAmount }.sumMoney()
    var rawRemaining = roundMoney(untaxableIncome + taxableIncome)
    if taxActive { rawRemaining = roundMoney(rawRemaining - taxSavings) }
    rawRemaining = roundMoney(rawRemaining - expenseSum)
    rawRemaining = roundMoney(rawRemaining + reallocated)
    let headerRemaining = rawRemaining.roundedAndNormalizedMoney()

    let effectiveExpenses = roundMoney(expenseSum + reallocOut - reallocIn)

    let headerBreakEven: Decimal
    if taxActive {
        let afterTax = roundMoney(taxableIncome - taxSavings)
        let available = roundMoney(afterTax + untaxableIncome)
        headerBreakEven = max(0, roundMoney(effectiveExpenses - available))
    } else {
        headerBreakEven = max(0, roundMoney(effectiveExpenses - roundMoney(taxableIncome + untaxableIncome)))
    }

    let covered = roundMoney(min(effectiveExpenses, untaxableIncome))
    let remainingAfterCovered = roundMoney(max(0, effectiveExpenses - covered))
    let divisor = 1 - taxRate
    let needed = divisor == 0 ? remainingAfterCovered : roundMoney(remainingAfterCovered / divisor)
    let grossNeeded = roundMoney(covered + needed)
    let headerIncomeNeeded = max(0, roundMoney(roundMoney(grossNeeded - untaxableIncome) - taxableIncome))

    return MonthHeaderTotals(
        incomeTotal: incomes.map { $0.amount }.sumMoney(),
        taxableIncomeTotal: taxableIncome,
        untaxableIncomeTotal: untaxableIncome,
        expenseTotal: expenseSum,
        distributedTaxes: distributedTaxes,
        taxTotal: summaryTax,
        taxSavingsTotal: taxSavings,
        reallocationInTotal: reallocIn,
        reallocationOutTotal: reallocOut,
        effectiveExpenses: effectiveExpenses,
        remaining: headerRemaining,
        breakEven: headerBreakEven,
        incomeNeeded: headerIncomeNeeded
    )
}

// MARK: - Month Data Cache Build (safe to call off the main actor)

/// Builds a MonthExpandedData for a single month: expanded arrays, O(1) per-day indices,
/// pre-filtered reallocations, the pre-sorted transaction list, and the header totals
/// MonthPageView displays (tax split, income/expense sums, Total Excess/Needed).
/// Operates purely on value types (`Income`/`Expense`/`Reallocation`/plain tax settings) —
/// safe to call from `buildMonthDataCache` off the main actor.
nonisolated func buildMonthData(incomes: [Income], expenses: [Expense],
                    reallocations: [Reallocation], odometerReadings: [OdometerReading] = [], ym: YearMonth,
                    weekStartDay: Int,
                    isTaxSavingsEnabled: Bool, taxSavingsPercentage: Double) -> MonthExpandedData {
    let activeIncomes = incomes.filter { $0.deletedDate == nil }
    let activeExpenses = expenses.filter { $0.deletedDate == nil }
    let inc = expandedIncomes(from: activeIncomes, month: ym.month, year: ym.year)
    let exp = expandedExpenses(from: activeExpenses, month: ym.month, year: ym.year)
    let cal = Calendar.current
    let incByDay = Dictionary(grouping: inc) { cal.component(.day, from: $0.date) }
    let expByDay = Dictionary(grouping: exp) { cal.component(.day, from: $0.date) }
    let activeReallocs  = reallocations.activeIn(yearMonth: ym)
    let reallocByDay = Dictionary(grouping: activeReallocs) { cal.component(.day, from: $0.date) }
    let positiveReallocs = reallocations.additionsIn(yearMonth: ym)
    let negativeReallocs = reallocations.deductionsIn(yearMonth: ym)
    let allTransactions: [TransactionItem] =
        inc.map { TransactionItem.income($0, adjustedDate: $0.date) } +
        exp.map { TransactionItem.expense($0, adjustedDate: $0.date) } +
        activeReallocs.map { TransactionItem.reallocation($0) }
    let sorted = allTransactions.sorted { t1, t2 in
        t1.sortDate != t2.sortDate ? t1.sortDate < t2.sortDate : t1.createdAt < t2.createdAt
    }
    let weeks = computeCalendarWeeks(year: ym.year, month: ym.month, weekStartDay: weekStartDay)
    // Pre-compute expense display dates so the render path only needs a dict lookup per row.
    var displayDates: [String: Date] = [:]
    displayDates.reserveCapacity(exp.count)
    for expense in exp {
        let key = "\(expense.id.uuidString)-\(expense.date.timeIntervalSince1970)"
        displayDates[key] = expenseDisplayDate(for: expense, ym: ym, calendar: cal)
    }
    // Pre-flatten the calendar grid so body avoids repeated flatMap + enumerated.
    let flatDays = weeks.flatMap { $0 }.enumerated().map { (offset: $0.offset, day: $0.element) }
    // Stable display order for the reallocations section; filtering preserves order.
    let sortedActiveReallocs = activeReallocs.sorted {
        if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
        return $0.id.uuidString < $1.id.uuidString
    }

    // Odometer readings dated within this month, for the Odometer section.
    let activeOdometerReadings = odometerReadings
        .filter { $0.date.year == ym.year && $0.date.month == ym.month }
        .sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }

    // Miles driven per vehicle this month: sum of each reading's own delta from the reading
    // immediately before it (chronologically), attributed to the month the later reading falls
    // in. A vehicle's very first reading ever has no predecessor to diff against, so it
    // contributes 0 — Miles Driven must always be an actual difference between two readings,
    // never a raw odometer value (which is what a lone first reading would otherwise show).
    var milesDrivenByVehicle: [String: Int] = [:]
    var milesDrivenByReadingID: [UUID: Int] = [:]
    for (vehicle, readingsForVehicle) in Dictionary(grouping: odometerReadings, by: \.vehicle) {
        let sortedReadings = readingsForVehicle.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
        var total = 0
        for i in 1..<sortedReadings.count {
            let reading = sortedReadings[i]
            let delta = reading.odometerValue - sortedReadings[i - 1].odometerValue
            milesDrivenByReadingID[reading.id] = delta
            guard reading.date.year == ym.year && reading.date.month == ym.month else { continue }
            total += delta
        }
        milesDrivenByVehicle[vehicle] = total
    }

    // Header totals — computed by the shared helper so the full-month figures here and the
    // live-filtered figures in MonthPageView's summary rows never drift apart.
    let headerTotals = computeHeaderTotals(incomes: inc, expenses: exp, reallocations: activeReallocs,
                                            isTaxSavingsEnabled: isTaxSavingsEnabled, taxSavingsPercentage: taxSavingsPercentage)

    return MonthExpandedData(expandedIncomes: inc, expandedExpenses: exp,
                             incomesByDay: incByDay, expensesByDay: expByDay,
                             reallocationsByDay: reallocByDay,
                             activeReallocations: activeReallocs,
                             positiveReallocations: positiveReallocs,
                             negativeReallocations: negativeReallocs,
                             sortedBaseTransactions: sorted,
                             calendarWeeks: weeks,
                             expenseDisplayDates: displayDates,
                             flatCalendarDays: flatDays,
                             summaryIncomeTotal: headerTotals.incomeTotal,
                             taxableIncomeTotal: headerTotals.taxableIncomeTotal,
                             untaxableIncomeTotal: headerTotals.untaxableIncomeTotal,
                             expenseTotal: headerTotals.expenseTotal,
                             distributedTaxes: headerTotals.distributedTaxes,
                             summaryTaxTotal: headerTotals.taxTotal,
                             taxSavingsTotal: headerTotals.taxSavingsTotal,
                             reallocationInTotal: headerTotals.reallocationInTotal,
                             reallocationOutTotal: headerTotals.reallocationOutTotal,
                             headerEffectiveExpenses: headerTotals.effectiveExpenses,
                             headerRemaining: headerTotals.remaining,
                             headerBreakEven: headerTotals.breakEven,
                             headerIncomeNeeded: headerTotals.incomeNeeded,
                             sortedActiveReallocations: sortedActiveReallocs,
                             activeOdometerReadings: activeOdometerReadings,
                             milesDrivenByVehicle: milesDrivenByVehicle,
                             milesDrivenByReadingID: milesDrivenByReadingID)
}

// MARK: - Yearly Miles Driven Helper

/// Total miles driven across all vehicles for a given year: sum of each reading's own delta
/// from the reading immediately before it (chronologically, per vehicle), attributed to the
/// year the later reading falls in. Mirrors the per-month calculation in `buildMonthData`.
nonisolated func totalMilesDriven(odometerReadings: [OdometerReading], year: Int) -> Int {
    var total = 0
    for (_, readingsForVehicle) in Dictionary(grouping: odometerReadings, by: \.vehicle) {
        let sortedReadings = readingsForVehicle.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
        for i in 1..<sortedReadings.count {
            let reading = sortedReadings[i]
            guard reading.date.year == year else { continue }
            total += reading.odometerValue - sortedReadings[i - 1].odometerValue
        }
    }
    return total
}

/// Builds the calendar day grid for a month, honoring the item's week-start-day preference.
/// Each inner array is one week row; `nil` entries are padding cells outside the month.
nonisolated func computeCalendarWeeks(year: Int, month: Int, weekStartDay: Int) -> [[Int?]] {
    let cal = Calendar.current
    let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
    let firstWeekday = cal.component(.weekday, from: firstOfMonth)
    var weeks: [[Int?]] = []
    var currentWeek: [Int?] = []
    let leadingNils = (firstWeekday - weekStartDay + 7) % 7
    for _ in 0..<leadingNils { currentWeek.append(nil) }
    for day in 1...daysInMonth {
        currentWeek.append(day)
        if currentWeek.count == 7 { weeks.append(currentWeek); currentWeek = [] }
    }
    if !currentWeek.isEmpty {
        while currentWeek.count < 7 { currentWeek.append(nil) }
        weeks.append(currentWeek)
    }
    return weeks
}

/// Builds `MonthExpandedData` for every month in `months`, off the main actor.
/// `@concurrent` forces the body onto the global concurrent executor rather than the caller's
/// actor (this project defaults nonisolated async functions to running on the caller's actor —
/// see `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT` — so without this attribute the
/// loop would silently stay on MainActor). Checks cancellation each iteration so a superseded
/// rebuild (a newer `dataVersion`) stops promptly instead of continuing to grind in the background.
@concurrent
func buildMonthDataCache(months: [YearMonth],
                          incomes: [Income], expenses: [Expense], reallocations: [Reallocation],
                          odometerReadings: [OdometerReading],
                          weekStartDay: Int,
                          isTaxSavingsEnabled: Bool, taxSavingsPercentage: Double) async -> [YearMonth: MonthExpandedData] {
    var result: [YearMonth: MonthExpandedData] = [:]
    for ym in months {
        guard !Task.isCancelled else { return result }
        result[ym] = buildMonthData(incomes: incomes, expenses: expenses,
                                     reallocations: reallocations, odometerReadings: odometerReadings, ym: ym,
                                     weekStartDay: weekStartDay,
                                     isTaxSavingsEnabled: isTaxSavingsEnabled,
                                     taxSavingsPercentage: taxSavingsPercentage)
    }
    return result
}

// MARK: - Expense Display Date Pre-computation

/// Computes the display date for an expanded expense occurrence in the given year-month.
/// Replicates MonthPageView.calculateDisplayDate but runs during the background cache build
/// so the render path only needs a single dictionary lookup per expense row.
nonisolated func expenseDisplayDate(for expense: Expense, ym: YearMonth, calendar: Calendar = .current) -> Date {
    let originalDay = calendar.component(.day, from: expense.date)
    let originalHour = calendar.component(.hour, from: expense.date)
    let originalMinute = calendar.component(.minute, from: expense.date)
    let isOriginalLastDay = expense.date.isLastDayOfMonth
    var components = DateComponents(year: ym.year, month: ym.month,
                                    hour: originalHour, minute: originalMinute)
    if isOriginalLastDay {
        if let base = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: base) {
            components.day = range.count
        } else {
            components.day = originalDay
        }
    } else {
        if let base = calendar.date(from: DateComponents(year: ym.year, month: ym.month)),
           let range = calendar.range(of: .day, in: .month, for: base) {
            components.day = min(originalDay, range.count)
        } else {
            components.day = originalDay
        }
    }
    return calendar.date(from: components) ?? expense.date
}

// MARK: - Shared Transaction Filter & Occurrence Key

/// Type filter for the month transaction list. Promoted to top level so the carousel
/// host (BudgetPageView), the page content (MonthPageView), and FilterOptionsSheet
/// can all reference it without a type prefix.
enum TransactionFilter: String, CaseIterable {
    case paymentPlans = "Payment Plans"
    case recurringExpenses = "Recurring Expenses"
    case oneTimeExpense = "One Time Expenses"
    case recurringIncome = "Recurring Income"
    case oneTimeIncome = "One Time Income"
    case taxableIncome = "Taxable Income"
    case otherIncome = "Other Income"
    case reallocations = "All Reallocations"
    case positiveReallocation = "Positive Reallocations"
    case negativeReallocation = "Negative Reallocations"
    case all = "All Transaction Types"
    case expenses = "All Expenses"
    case income = "All Income"
    /// Parent-level filter for the Odometer bucket, toggled by the "All Vehicles" row.
    /// A specific vehicle selection (`selectedVehicleFilter`) acts like a subtype of this —
    /// its presence alone marks the bucket active, mirroring how an income/expense subtype's
    /// presence marks that bucket active without the parent filter also being present.
    case odometer = "Odometer"
}

/// Uniquely identifies a single occurrence of an item (recurring items share a UUID but
/// have distinct dates). Used by the shared selection sets owned by the carousel host.
struct OccurrenceKey: Hashable {
    let id: UUID
    let date: Date
}

// MARK: - Shared Month Item Filters & Expansion

/// Incomes active in the given month (one-time on that month, or recurring active that month).
nonisolated func monthlyIncomes(from incomes: [Income], month: Int, year: Int) -> [Income] {
    incomes.filter { income in
        (income.date.year == year && income.date.month == month)
        || (income.isRecurring && isItemActiveInMonth(date: income.date, endDate: income.endDate, targetMonth: month, targetYear: year, frequency: income.recurringFrequency.rawValue, rule: income.resolvedRule))
    }
}

/// Expenses active in the given month (one-time on that month, or recurring/payment-plan active that month).
nonisolated func monthlyExpenses(from expenses: [Expense], month: Int, year: Int) -> [Expense] {
    expenses.filter { expense in
        (expense.date.year == year && expense.date.month == month)
        || ((expense.isRecurring || expense.isMonthlyPaymentPlan) && isItemActiveInMonth(date: expense.date, endDate: expense.endDate, targetMonth: month, targetYear: year, frequency: expense.effectiveFrequency, rule: expense.resolvedRule))
    }
}

/// Expands recurring incomes into individual dated occurrences for the entire month.
nonisolated func expandedIncomes(from incomes: [Income], month: Int, year: Int) -> [Income] {
    let calendar = Calendar.current
    let monthItems = monthlyIncomes(from: incomes, month: month, year: year)
    guard let monthRange = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()) else {
        return monthItems
    }
    var result: [Income] = []
    for income in monthItems {
        if income.isRecurring {
            for day in monthRange {
                if shouldRecurringItemAppearOnDay(startDate: income.date, endDate: income.endDate, frequency: income.recurringFrequency.rawValue, day: day, month: month, year: year, rule: income.resolvedRule),
                   let occurrence = income.withOccurrenceDate(day: day, month: month, year: year) {
                    result.append(occurrence)
                }
            }
        } else {
            result.append(income)
        }
    }
    return result
}

/// Expands recurring expenses into individual dated occurrences for the entire month.
nonisolated func expandedExpenses(from expenses: [Expense], month: Int, year: Int) -> [Expense] {
    let calendar = Calendar.current
    let monthItems = monthlyExpenses(from: expenses, month: month, year: year)
    guard let monthRange = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()) else {
        return monthItems
    }
    var result: [Expense] = []
    for expense in monthItems {
        if expense.isRecurring || expense.isMonthlyPaymentPlan {
            for day in monthRange {
                if shouldRecurringItemAppearOnDay(startDate: expense.date, endDate: expense.endDate, frequency: expense.effectiveFrequency, day: day, month: month, year: year, rule: expense.resolvedRule),
                   let occurrence = expense.withOccurrenceDate(day: day, month: month, year: year) {
                    result.append(occurrence)
                }
            }
        } else {
            result.append(expense)
        }
    }
    return result
}

// MARK: - Month Relation & Default Date

/// Whether a year-month is the current calendar month, in the past, or in the future.
enum MonthRelation { case current, past, future }

func monthRelation(for yearMonth: YearMonth, now: Date = Date()) -> MonthRelation {
    if yearMonth.year == now.year && yearMonth.month == now.month { return .current }
    if yearMonth.year < now.year || (yearMonth.year == now.year && yearMonth.month < now.month) { return .past }
    return .future
}

/// Default day for a new item in a month: the single selected day if exactly one is chosen,
/// otherwise today for the current month, last day for past, 1 for future.
func defaultDay(for yearMonth: YearMonth, selectedDays: Set<Int>) -> Int {
    if selectedDays.count == 1, let day = selectedDays.first { return day }
    switch monthRelation(for: yearMonth) {
    case .current: return Date().day
    case .past:
        let comps = DateComponents(year: yearMonth.year, month: yearMonth.month + 1, day: 1)
        if let next = Calendar.current.date(from: comps),
           let last = Calendar.current.date(byAdding: .day, value: -1, to: next) {
            return last.day
        }
        return 28
    case .future: return 1
    }
}

/// Default date+time for a new item in a month: the single selected day if exactly one is chosen,
/// otherwise now for the current month, 23:59 last day for past, 00:00 first day for future.
func defaultDate(for yearMonth: YearMonth, selectedDays: Set<Int>) -> Date {
    let cal = Calendar.current
    if selectedDays.count == 1, let day = selectedDays.first {
        let today = Date()
        let comps = DateComponents(year: yearMonth.year, month: yearMonth.month, day: day)
        guard let dayDate = cal.date(from: comps) else { return today }
        let dayStart = cal.startOfDay(for: dayDate)
        let todayStart = cal.startOfDay(for: today)
        if dayStart == todayStart {
            return today
        } else if dayStart < todayStart {
            return cal.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: day, hour: 23, minute: 59, second: 0)) ?? today
        } else {
            return cal.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: day, hour: 0, minute: 0, second: 0)) ?? today
        }
    }
    switch monthRelation(for: yearMonth) {
    case .current: return Date()
    case .past:
        let comps = DateComponents(year: yearMonth.year, month: yearMonth.month + 1, day: 1, hour: 0, minute: 0, second: 0)
        if let next = cal.date(from: comps), let last = cal.date(byAdding: .minute, value: -1, to: next) { return last }
        return cal.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: 28, hour: 23, minute: 59, second: 0)) ?? Date()
    case .future:
        return cal.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: 1, hour: 0, minute: 0, second: 0)) ?? Date()
    }
}

// MARK: - Carousel Month Range

/// Adds `months` to a year-month, normalizing the year.
nonisolated func offsetYearMonth(_ base: YearMonth, by months: Int) -> YearMonth {
    let cal = Calendar.current
    guard let baseDate = cal.date(from: DateComponents(year: base.year, month: base.month)),
          let shifted = cal.date(byAdding: .month, value: months, to: baseDate) else { return base }
    return YearMonth(year: cal.component(.year, from: shifted), month: cal.component(.month, from: shifted))
}

/// Every year-month from `lower` through `upper` inclusive, ascending.
func yearMonths(from lower: YearMonth, through upper: YearMonth) -> [YearMonth] {
    guard lower <= upper else { return [lower] }
    var result: [YearMonth] = []
    var current = lower
    while current <= upper {
        result.append(current)
        current = offsetYearMonth(current, by: 1)
        if result.count > 1200 { break } // safety cap (~100 years)
    }
    return result
}

// MARK: - Transaction Type Default Selection

extension Set where Element == TransactionFilter {
    static var defaultSelection: Set<TransactionFilter> { [.income, .expenses, .reallocations, .odometer] }
    var isDefaultSelection: Bool { self == .defaultSelection }
}

// MARK: - Combined Filter and Type Sheet

struct FilterAndTypeSheet: View {
    @Binding var selectedTransactionTypes: Set<TransactionFilter>
    @Binding var selectedTransactionCategories: Set<String>
    @Binding var selectedVehicle: String?
    @Bindable var item: Item
    let month: Int
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @HighlightColorStorage private var highlightColor
    @AppStorage("transactionCategories") private var storedCategories: String = "[]"
    @AppStorage("vehicles") private var storedVehicles: String = "[]"

    // MARK: - Carousel state
    @AppStorage("filterSheetLastPage") private var persistedPage: Int = 0
    @State private var selectedPage: Int = 0
    @State private var jumpTarget: Int? = nil
    @State private var isCarouselAnimating = false
    @State private var carouselDriver = CarouselJumpDriver()

    // MARK: - Type page state
    @State private var typeCounts: [TransactionFilter: Int] = [:]

    // MARK: - Filter page state
    @State private var localCategories: [String] = []
    @State private var localHiddenCategories: [String] = []
    @State private var categoryCounts: [String: Int] = [:]
    @State private var countsLoaded = false
    @State private var showingHiddenCategories = false
    @State private var newCategoryName: String = ""
    @State private var showingAddAlert = false
    @State private var categoryToEdit: String = ""
    @State private var editCategoryName: String = ""
    @State private var showingEditAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var categoryToDelete: String? = nil
    private let protectedCategories: Set<String> = ["Reimbursed", "Reimbursement", "Pending Reimbursement"]

    // MARK: - Type selection logic

    private static let incomeSubTypes: Set<TransactionFilter> = [.otherIncome, .taxableIncome, .recurringIncome, .oneTimeIncome]
    private static let expenseSubTypes: Set<TransactionFilter> = [.recurringExpenses, .paymentPlans, .oneTimeExpense]
    private static let reallocationSubTypes: Set<TransactionFilter> = [.positiveReallocation, .negativeReallocation]

    private func selectType(_ filter: TransactionFilter) {
        if selectedTransactionTypes.isDefaultSelection {
            selectedTransactionTypes = [filter]
            return
        }
        if selectedTransactionTypes.contains(filter) {
            if selectedTransactionTypes.count <= 1 {
                if Self.incomeSubTypes.contains(filter) {
                    selectedTransactionTypes = [.income]
                } else if Self.expenseSubTypes.contains(filter) {
                    selectedTransactionTypes = [.expenses]
                } else if Self.reallocationSubTypes.contains(filter) {
                    selectedTransactionTypes = [.reallocations]
                }
                return
            }
            selectedTransactionTypes.remove(filter)
        } else {
            selectedTransactionTypes.insert(filter)
            switch filter {
            case .income:
                selectedTransactionTypes.subtract(Self.incomeSubTypes)
            case .expenses:
                selectedTransactionTypes.subtract(Self.expenseSubTypes)
            case .reallocations:
                selectedTransactionTypes.subtract(Self.reallocationSubTypes)
            case _ where Self.incomeSubTypes.contains(filter):
                selectedTransactionTypes.remove(.income)
            case _ where Self.expenseSubTypes.contains(filter):
                selectedTransactionTypes.remove(.expenses)
            case _ where Self.reallocationSubTypes.contains(filter):
                selectedTransactionTypes.remove(.reallocations)
            default:
                break
            }
        }
    }

    /// "All Vehicles" (`vehicle == nil`) is the parent-level filter for the Odometer bucket —
    /// tapping it toggles the whole bucket exactly like tapping Income/Expenses/Reallocations
    /// (combinable with them, not exclusive), via the same `selectType` used for those.
    ///
    /// A specific vehicle acts like a subtype: its presence in `selectedVehicleFilter` alone
    /// marks the bucket active (see `hasOdometerFilter`), so selecting one drops the redundant
    /// `.odometer` parent marker — mirroring how selecting e.g. `.taxableIncome` drops `.income`.
    /// Tapping the already-selected vehicle again reverts to the bare parent bucket (still
    /// showing Odometer, just unnarrowed), mirroring a lone subtype toggling off to its parent.
    private func selectVehicle(_ vehicle: String?) {
        guard let vehicle else {
            selectType(.odometer)
            selectedVehicle = nil
            return
        }
        if selectedTransactionTypes.isDefaultSelection {
            selectedTransactionTypes = [.odometer]
            selectedVehicle = vehicle
            return
        }
        if selectedVehicle == vehicle {
            selectedVehicle = nil
            selectedTransactionTypes.insert(.odometer)
        } else {
            selectedVehicle = vehicle
            selectedTransactionTypes.remove(.odometer)
        }
    }

    // MARK: - Filter page helpers

    private var visibleCategories: [String] {
        let hidden = Set(item.hiddenFilterCategories?.asCategories ?? [])
        return storedCategories.asCategories.filter { !hidden.contains($0) }
    }

    private func hideCategory(_ category: String) {
        selectedTransactionCategories.remove(category)
        if !localHiddenCategories.contains(category) {
            localHiddenCategories.append(category)
            item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        }
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
        selectedTransactionCategories.remove(category)
        if selectedTransactionCategories.isEmpty {
            selectedTransactionCategories = [SettingsDefault.uncategorizedSentinel]
        }
        localHiddenCategories.removeAll { $0 == category }
        item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        updateItemsForDeletedCategory(category, modelContext: modelContext)
        NotificationCenter.default.post(name: .categoryDeleted, object: nil, userInfo: ["name": category])
    }

    private func renameCategory(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty, trimmed != old else { return }
        var cats = storedCategories.asCategories
        if let index = cats.firstIndex(of: old) {
            cats[index] = trimmed
            storedCategories = cats.asAppStorageString
        }
        if selectedTransactionCategories.contains(old) {
            selectedTransactionCategories.remove(old)
            selectedTransactionCategories.insert(trimmed)
        }
        if let idx = localHiddenCategories.firstIndex(of: old) {
            localHiddenCategories[idx] = trimmed
            item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        }
        updateItemsForRenamedCategory(from: old, to: trimmed, modelContext: modelContext)
        NotificationCenter.default.post(name: .categoryRenamed, object: nil, userInfo: ["oldName": old, "newName": trimmed])
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                Group {
                    if countsLoaded {
                        filterPage
                    } else {
                        Color.clear
                    }
                }
                .containerRelativeFrame([.horizontal, .vertical])
                .id(0)
                typePage
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(1)
            }
            .scrollTargetLayout()
            .background(CarouselScrollFinder(driver: carouselDriver))
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding<Int?>(
            get: { isCarouselAnimating ? nil : selectedPage },
            set: { if let p = $0, !isCarouselAnimating { selectedPage = p } }
        ))
        .scrollDisabled(isCarouselAnimating)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onChange(of: jumpTarget) { _, target in
            guard let target else { return }
            guard let sv = carouselDriver.scrollView else {
                selectedPage = target
                jumpTarget = nil
                return
            }
            let targetX = CGFloat(target) * sv.bounds.width
            isCarouselAnimating = true
            carouselDriver.animate(toX: targetX, duration: 0.5) {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    self.selectedPage = target
                    self.isCarouselAnimating = false
                }
            }
            jumpTarget = nil
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if !selectedTransactionCategories.isEmpty {
                        selectedTransactionCategories = []
                    }
                    if !selectedTransactionTypes.isDefaultSelection {
                        selectedTransactionTypes = .defaultSelection
                    }
                    if selectedVehicle != nil {
                        selectedVehicle = nil
                    }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .tint(.primary)
                .disabled(selectedTransactionCategories.isEmpty && selectedTransactionTypes.isDefaultSelection && selectedVehicle == nil)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    newCategoryName = ""
                    showingAddAlert = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .tint(.primary)
                .disabled(selectedPage != 0)
            }
        }
        .navigationDestination(isPresented: $showingHiddenCategories) {
            HiddenCategoriesPage(localHiddenCategories: $localHiddenCategories, item: item, month: month, year: year)
        }
        .onAppear {
            selectedPage = persistedPage
            localCategories = storedCategories.asCategories
            localHiddenCategories = item.hiddenFilterCategories?.asCategories ?? []
            typeCounts = buildTypeCounts(for: item, month: month, year: year)
            categoryCounts = buildCategoryCounts(for: item, month: month, year: year)
            countsLoaded = true
            carouselDriver.onUserDragBegan = {
                guard !isCarouselAnimating else { return }
                NotificationCenter.default.post(name: .scrollSheetPageToFirstSection, object: nil)
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            persistedPage = newValue
        }
        .onChange(of: storedCategories) { _, newValue in
            let updated = newValue.asCategories
            if updated != localCategories { localCategories = updated }
        }
        .onChange(of: item.hiddenFilterCategories) { _, newValue in
            localHiddenCategories = newValue?.asCategories ?? []
            modelContext.saveWithLogging("combined filter sheet")
        }
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

    // MARK: - Type Page

    private var typePage: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    typeRow(.income)
                        .id("type-page-top")
                    typeRow(.otherIncome)
                    typeRow(.taxableIncome)
                    typeRow(.recurringIncome)
                    typeRow(.oneTimeIncome)
                } header: {
                    HStack {
                        Text("Types")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                        Spacer()
                    }
                }
                Section {
                    typeRow(.expenses)
                    typeRow(.paymentPlans)
                    typeRow(.recurringExpenses)
                    typeRow(.oneTimeExpense)
                }
                Section {
                    typeRow(.reallocations)
                    typeRow(.positiveReallocation)
                    typeRow(.negativeReallocation)
                }
                Section {
                    vehicleRow(nil)
                    ForEach(storedVehicles.asCategories, id: \.self) { vehicle in
                        vehicleRow(vehicle)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .tint(.primary)
            .onReceive(NotificationCenter.default.publisher(for: .scrollSheetPageToFirstSection)) { _ in
                guard selectedPage == 1 else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                    proxy.scrollTo("type-page-top", anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func typeRow(_ filter: TransactionFilter) -> some View {
        Button {
            selectType(filter)
        } label: {
            HStack {
                Text(filter.rawValue)
                    .foregroundStyle(.primary)
                Text("\(typeCounts[filter, default: 0])")
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedTransactionTypes.contains(filter) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(highlightColor)
                }
            }
        }
        .tint(.primary)
    }

    /// Vehicle filter row. `nil` represents "All Vehicles" — the parent-level Odometer filter,
    /// checked only when that bucket is actually active (not merely whenever no specific
    /// vehicle is narrowed, which is also true while the bucket is inactive entirely).
    @ViewBuilder
    private func vehicleRow(_ vehicle: String?) -> some View {
        Button {
            selectVehicle(vehicle)
        } label: {
            HStack {
                Text(vehicle ?? "All Vehicles")
                    .foregroundStyle(.primary)
                Spacer()
                if isVehicleRowChecked(vehicle) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(highlightColor)
                }
            }
        }
        .tint(.primary)
    }

    private func isVehicleRowChecked(_ vehicle: String?) -> Bool {
        guard vehicle == nil else { return selectedVehicle == vehicle }
        return selectedVehicle == nil && selectedTransactionTypes.contains(.odometer)
    }

    // MARK: - Filter Page

    private var filterPage: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                Button {
                    selectedTransactionCategories = []
                } label: {
                    HStack {
                        Text("All")
                            .foregroundStyle(.primary)
                        Text("\(categoryCounts.values.reduce(0, +))")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        if selectedTransactionCategories.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(highlightColor)
                        }
                    }
                }
                .tint(.primary)
                .id("filter-page-top")

                ForEach(visibleCategories, id: \.self) { category in
                    filterCategoryRow(for: category)
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
                    if selectedTransactionCategories == [SettingsDefault.uncategorizedSentinel] {
                        selectedTransactionCategories = []
                    } else {
                        selectedTransactionCategories = [SettingsDefault.uncategorizedSentinel]
                    }
                } label: {
                    HStack {
                        Text("Uncategorized")
                            .foregroundStyle(.primary)
                        Text("\(categoryCounts[SettingsDefault.uncategorizedSentinel, default: 0])")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        if selectedTransactionCategories == [SettingsDefault.uncategorizedSentinel] {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(highlightColor)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Categories")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .textCase(nil)
                    Spacer()
                }
            }

            Section {
                Button {
                    showingHiddenCategories = true
                } label: {
                    HStack {
                        Text("Hidden Categories")
                        Text("\(localHiddenCategories.filter { localCategories.contains($0) }.count)")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .scrollContentBackground(.hidden)
        .tint(.primary)
        .onReceive(NotificationCenter.default.publisher(for: .scrollSheetPageToFirstSection)) { _ in
            guard selectedPage == 0 else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                proxy.scrollTo("filter-page-top", anchor: .center)
            }
        }
        }
    }

    @ViewBuilder
    private func filterCategoryRow(for category: String) -> some View {
        Button {
            selectedTransactionCategories.remove(SettingsDefault.uncategorizedSentinel)
            if selectedTransactionCategories.contains(category) {
                selectedTransactionCategories.remove(category)
            } else {
                selectedTransactionCategories.insert(category)
            }
        } label: {
            HStack {
                Text(category)
                    .foregroundStyle(.primary)
                Text("\(categoryCounts[category, default: 0])")
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedTransactionCategories.contains(category) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(highlightColor)
                }
            }
        }
        .contextMenu {
            if !protectedCategories.contains(category) {
                Button {
                    categoryToEdit = category
                    editCategoryName = category
                    showingEditAlert = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.primary)
            }
            Button { hideCategory(category) } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            .tint(.primary)
            if !protectedCategories.contains(category) {
                Divider()
                Button(role: .destructive) {
                    categoryToDelete = category
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }
}
