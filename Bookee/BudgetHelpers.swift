//
//  BudgetHelpers.swift
//  Bookee
//
//  Shared date, budget, and occurrence helpers used across budget views.
//

import SwiftUI
import SwiftData

// MARK: - Shared Last-Day-Of-Month Helper

func isLastDayOfMonth(year: Int, month: Int, day: Int) -> Bool {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))?.isLastDayOfMonth ?? false
}

// MARK: - Shared Expense-to-Income Conversion

/// Creates a non-taxable, non-recurring Income from an Expense (used by payOffExpense in both budget views).
func makeIncomeFromExpense(_ expense: Expense) -> Income {
    Income(
        name: expense.name,
        amount: expense.amount,
        date: Date(),
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
/// Used by both BudgetVisualizerPageView and IncomePageView.
struct YearMonth: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    let month: Int

    var id: String { "\(year)-\(month)" }
    var displayName: String { monthDisplayName(month) }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
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
func shouldRecurringItemAppearOnDay(startDate: Date, endDate: Date?, frequency: String, day: Int, month: Int, year: Int, rule: RecurrenceRule? = nil) -> Bool {
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
func isItemActiveInMonth(date: Date, endDate: Date?, targetMonth: Int, targetYear: Int, frequency: String? = nil, rule: RecurrenceRule? = nil) -> Bool {
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
            case .dayOfMonth: return true
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

// MARK: - Shared Occurrence-Date Finder

/// Finds the occurrence date for a recurring item in the viewed month/day.
func findOccurrenceDateForRecurringItem(startDate: Date, endDate: Date?, frequency: String, inMonth month: Int, year: Int, onDay day: Int?, rule: RecurrenceRule? = nil) -> Date? {
    let calendar = Calendar.current
    let build: (Int) -> Date? = { d in
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = d
        comps.hour   = calendar.component(.hour,   from: startDate)
        comps.minute = calendar.component(.minute, from: startDate)
        return calendar.date(from: comps)
    }
    if let specificDay = day {
        guard shouldRecurringItemAppearOnDay(startDate: startDate, endDate: endDate, frequency: frequency, day: specificDay, month: month, year: year, rule: rule) else { return nil }
        return build(specificDay)
    }
    guard let monthRange = calendar.range(of: .day, in: .month, for: calendar.firstOfMonth(month: month, year: year) ?? Date()) else { return nil }
    for d in monthRange {
        if shouldRecurringItemAppearOnDay(startDate: startDate, endDate: endDate, frequency: frequency, day: d, month: month, year: year, rule: rule) {
            return build(d)
        }
    }
    return nil
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
    let data = item.decodeBudgetData()
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

    for expense in data?.expenses ?? [] {
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

    for income in data?.incomes ?? [] {
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
    }
}

// MARK: - Budget Data Persistence Helper

/// Encodes all four budget arrays into `item`'s external storage and saves the SwiftData context.
/// Shared by BudgetVisualizerPageView and MonthDetailsPageView so the body exists in one place.
func saveBudgetData(
    to item: Item,
    expenses: [Expense], incomes: [Income],
    attachments: [BudgetAttachment], reallocations: [Reallocation]
) {
    item.lastModifiedDate = Date()
    do {
        try item.encodeBudgetData(expenses: expenses, incomes: incomes,
                                   attachments: attachments, reallocations: reallocations)
        print("💾 Saved \(expenses.count) expense(s), \(incomes.count) income(s), \(attachments.count) attachment(s), and \(reallocations.count) reallocation(s)")
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
) -> Double {
    let isMovingBackwards = (fromYear > toYear) || (fromYear == toYear && fromMonth > toMonth)

    let incomeAmounts: [(amount: Double, isTaxable: Bool)] = incomes.compactMap { income in
        guard let amount = effectiveMonthlyAmount(for: income, month: fromMonth, year: fromYear) else { return nil }
        return (amount, income.isTaxable)
    }
    let totalIncome = incomeAmounts.map { $0.amount }.sumMoney()
    let taxableIncome = incomeAmounts.filter { $0.isTaxable }.map { $0.amount }.sumMoney()

    let existingReallocationsIn  = reallocations.additionsIn(yearMonth: YearMonth(year: fromYear, month: fromMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()
    let existingReallocationsOut = reallocations.deductionsIn(yearMonth: YearMonth(year: fromYear, month: fromMonth), excluding: excludingIDs).map { $0.amount }.sumMoney()

    let applyTax: (Double) -> Double = { available in
        guard item.isTaxActive else {
            return max(0, available.roundedMoney())
        }
        let tax = taxableIncome.taxAmount(rate: item.taxRate)
        return max(0, roundMoney(available - tax))
    }

    if isMovingBackwards {
        let available = roundMoney(roundMoney(totalIncome + existingReallocationsIn) - existingReallocationsOut)
        return applyTax(available)
    }

    let totalExpenses = expenses.compactMap { effectiveMonthlyAmount(for: $0, month: fromMonth, year: fromYear) }.sumMoney()
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
func effectiveMonthlyAmount<T: RecurringItem>(for item: T, month: Int, year: Int) -> Double? {
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
        return roundMoney(item.amount * Double(occ))
    } else {
        guard item.date.year == year && item.date.month == month else { return nil }
        return item.amount
    }
}

// MARK: - Break-Even Deficit

/// Computes how much additional income is needed to cover expenses after tax.
/// Shared by ReallocationViews and BudgetVisualizerPageView's break-even calculation.
/// - Note: Does NOT use the income-needed divisor formula (1 - taxRate) — that is a separate
///   calculation in BudgetVisualizerPageView.computeMonthMetrics and must stay at full precision.
func breakEvenDeficit(
    taxableIncome: Double,
    untaxableIncome: Double,
    expenses: Double,
    isTaxActive: Bool,
    taxRate: Double
) -> Double {
    if isTaxActive {
        let tax = taxableIncome.taxAmount(rate: taxRate)
        let afterTax = roundMoney(taxableIncome - tax)
        let available = roundMoney(afterTax + untaxableIncome)
        return max(0, roundMoney(expenses - available))
    } else {
        let totalIncome = roundMoney(taxableIncome + untaxableIncome)
        return max(0, roundMoney(expenses - totalIncome))
    }
}
