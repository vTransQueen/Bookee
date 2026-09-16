//
//  MoneyUtilities.swift
//  Bookee
//
//  Created by Kara Eveland on 5/6/26.
//

import Foundation

// MARK: - Decimal Money Utilities

/// All money fields (Expense.amount, Income.amount, Reallocation.amount) are stored as `Decimal`,
/// which is base-10 and represents 0.1, 12.5, 0.01 etc. exactly. Rounding via NSDecimalRound
/// defines the canonical 2dp cents value; it does not hide IEEE 754 representation error.
///
/// Rules:
/// - Round to 2dp via roundedMoney() after every arithmetic operation.
/// - Compare money with == or < > 0 after rounding (no tolerance needed with Decimal).
/// - Sum via sumMoney() (exact for Decimal inputs; defensive final round).
/// - Decode stored JSON via decodeMoney(forKey:) — NOT the default Decimal path (which
///   routes through Double and re-introduces FP error for historically-written values).
///
/// The legacy Double extensions below support taxSavingsPercentage (stored as Double in SwiftData)
/// and UI-layer percentage formatting only. Do not use them for money amounts.
nonisolated extension Decimal {
    /// Rounds to 2 decimal places, round-half-away-from-zero (.plain).
    /// No epsilon nudge needed — Decimal represents 1.005 exactly.
    func roundedMoney() -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }

    /// True when value is exactly zero after canonical 2dp rounding.
    var isEffectivelyZero: Bool { self == 0 }

    /// True when value is strictly less than zero.
    var isEffectivelyNegative: Bool { self < 0 }

    /// True when value is strictly greater than zero.
    var isEffectivelyPositive: Bool { self > 0 }

    /// True when two values are exactly equal (Decimal equality is exact after rounding).
    func isEffectivelyEqual(to other: Decimal) -> Bool { self == other }

    /// Decimal has no −0.0, so this is an identity operation.
    var normalizedZero: Decimal { self }

    /// Rounds and normalises in one step (normalisation is a no-op for Decimal).
    func roundedAndNormalizedMoney() -> Decimal { roundedMoney() }

    /// Tax amount at the given rate, rounded to cents.
    func taxAmount(rate: Decimal) -> Decimal { roundMoney(self * rate) }
}

nonisolated extension Sequence where Element == Decimal {
    /// Exact sum rounded to 2dp. Per-step rounding is not needed since Decimal addition is exact.
    func sumMoney() -> Decimal {
        reduce(0, +).roundedMoney()
    }
}

// MARK: - Decimal Free Functions

/// Free-function alias for Decimal.roundedMoney() — keeps existing call sites unchanged.
@inline(__always)
nonisolated func roundMoney(_ value: Decimal) -> Decimal { value.roundedMoney() }

/// Floor-division per-payment amount, exact via integer-cent arithmetic.
/// Returns nil if total is not positive or payments is zero.
nonisolated func floorCentsPerPayment(total: Decimal, payments: Int) -> Decimal? {
    guard total.isEffectivelyPositive, payments > 0 else { return nil }
    let totalCents = NSDecimalNumber(decimal: total.roundedMoney() * 100).int64Value
    let centsPerPayment = totalCents / Int64(payments)
    return Decimal(centsPerPayment) / 100
}

// MARK: - JSON Decode Helpers

nonisolated extension KeyedDecodingContainer {
    /// Decodes a historically-Double-encoded JSON money value as a clean 2dp Decimal.
    /// Reads the raw JSON as Double (preserving what was written), converts via the
    /// shortest-round-trip String description, then rounds to 2dp. This prevents
    /// Decimal(Double) from re-introducing IEEE 754 representation error.
    func decodeMoney(forKey key: Key) throws -> Decimal {
        let d = try decode(Double.self, forKey: key)
        guard d.isFinite else { return 0 }
        return (Decimal(string: String(d)) ?? Decimal(d)).roundedMoney()
    }

    func decodeMoneyIfPresent(forKey key: Key) throws -> Decimal? {
        guard let d = try decodeIfPresent(Double.self, forKey: key) else { return nil }
        guard d.isFinite else { return 0 }
        return (Decimal(string: String(d)) ?? Decimal(d)).roundedMoney()
    }
}

// MARK: - Legacy Double Utilities (taxSavingsPercentage / UI percentage only)

nonisolated extension Double {
    /// Rounds a percentage or legacy value to 2 decimal places.
    /// Used for taxSavingsPercentage (stored as Double in SwiftData) and percentage formatters.
    func roundedMoney() -> Double {
        let epsilon: Double = self >= 0 ? 1e-9 : -1e-9
        return ((self + epsilon) * 100).rounded() / 100
    }

    var isEffectivelyZero: Bool { abs(self) < 0.0001 }
    var isEffectivelyNegative: Bool { self < -0.0001 }
    var isEffectivelyPositive: Bool { self > 0.0001 }

    func isEffectivelyEqual(to other: Double) -> Bool { (self - other).isEffectivelyZero }

    var normalizedZero: Double { self == -0.0 ? 0.0 : self }

    func roundedAndNormalizedMoney() -> Double {
        let rounded = self.roundedMoney()
        if rounded.isEffectivelyZero { return 0.0 }
        return rounded == -0.0 ? 0.0 : rounded
    }

    func taxAmount(rate: Double) -> Double { roundMoney(self * rate) }
}

nonisolated extension Sequence where Element == Double {
    func sumMoney() -> Double {
        self.reduce(0.0) { ($0 + $1).roundedMoney() }.roundedMoney()
    }
}

/// Legacy alias for Double.roundedMoney().
@inline(__always)
nonisolated func roundMoney(_ value: Double) -> Double { value.roundedMoney() }

nonisolated func floorCentsPerPayment(total: Double, payments: Int) -> Double? {
    guard total.isEffectivelyPositive, payments > 0 else { return nil }
    let totalCents = Int((total.roundedMoney() * 100.0).rounded())
    let centsPerPayment = totalCents / payments
    return roundMoney(Double(centsPerPayment) / 100.0)
}

// MARK: - Date Utilities

nonisolated extension Date {
    /// The day-of-month component of this date.
    var day: Int { Calendar.current.component(.day, from: self) }

    /// The month component of this date (1 = January, 12 = December).
    var month: Int { Calendar.current.component(.month, from: self) }

    /// The year component of this date.
    var year: Int { Calendar.current.component(.year, from: self) }

    /// Returns true when this date falls on the last day of its month.
    var isLastDayOfMonth: Bool {
        let calendar = Calendar.current
        let y = calendar.component(.year,  from: self)
        let m = calendar.component(.month, from: self)
        let d = calendar.component(.day,   from: self)
        guard let monthDate = calendar.date(from: DateComponents(year: y, month: m)),
              let range = calendar.range(of: .day, in: .month, for: monthDate) else { return false }
        return d == range.count
    }
}

// MARK: - Timestamp Helper

/// Returns the current date formatted as "yyyy-MM-dd_HH-mm-ss" — the canonical file-safe timestamp.
func makeTimestamp(from date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter.string(from: date)
}

// MARK: - Photo Filename Helper

func makePhotoFileName() -> String {
    "photo_\(makeTimestamp()).jpg"
}

// MARK: - Month Name Helper

/// Returns the full month name for a 1-based month number (1 = January … 12 = December).
nonisolated func monthDisplayName(_ month: Int) -> String {
    Calendar.current.monthSymbols[month - 1]
}

// MARK: - Tax Distribution Helper

/// Distributes tax amounts across incomes so per-income taxes sum exactly to the total.
///
/// Example:
/// - Income 1: $7.10 × 11% = $0.781 → floor $0.78, remainder 0.1
/// - Income 2: $56.80 × 11% = $6.248 → floor $6.24, remainder 8
/// - Total: $63.90 × 11% = $7.029 → $7.03
/// - $0.78 + $6.24 = $7.02 ✗ — missing cent goes to largest-remainder bucket (income 2)
/// - $0.78 + $6.25 = $7.03 ✓
nonisolated struct TaxDistributionHelper {
    /// Generic largest-remainder distribution over Decimal buckets.
    /// Sum of distributed taxes equals roundMoney(totalTaxableAmount × taxRate) exactly.
    static func distributedTaxAmounts<Key: Hashable>(
        buckets: [(key: Key, taxableAmount: Decimal)],
        taxRate: Decimal
    ) -> [Key: Decimal] {
        let activeBuckets = buckets.filter { $0.taxableAmount.isEffectivelyPositive }
        guard !activeBuckets.isEmpty else { return [:] }

        let totalIncome = activeBuckets.map { $0.taxableAmount }.sumMoney()
        let exactTotalTax = roundMoney(totalIncome * taxRate)

        let oneCent = Decimal(1) / 100
        var taxData: [(key: Key, floor: Decimal, remainder: Decimal)] = activeBuckets.map { bucket in
            let amountCents = NSDecimalNumber(decimal: bucket.taxableAmount * 100).int64Value
            let basisPoints = NSDecimalNumber(decimal: (taxRate * 10000).roundedMoney()).int64Value
            let exactCents = Decimal(amountCents * basisPoints) / 10000
            var floorResult = Decimal()
            var exactCentsCopy = exactCents
            NSDecimalRound(&floorResult, &exactCentsCopy, 0, .down)
            let floorTax = floorResult / 100
            return (key: bucket.key, floor: floorTax, remainder: exactCents - floorResult)
        }

        let totalFloor = taxData.map { $0.floor }.sumMoney()
        let centsNeeded = max(0,
            NSDecimalNumber(decimal: (exactTotalTax * 100).roundedMoney()).int64Value -
            NSDecimalNumber(decimal: (totalFloor * 100).roundedMoney()).int64Value
        )

        taxData.sort { $0.remainder > $1.remainder }

        var result: [Key: Decimal] = [:]
        for (index, data) in taxData.enumerated() {
            result[data.key] = roundMoney(data.floor + (index < Int(centsNeeded) ? oneCent : 0))
        }
        return result
    }

    /// Distributes tax for a collection of incomes sharing the same rate.
    static func distributedTaxAmounts(for incomes: [Income], taxRate: Decimal) -> [UUID: Decimal] {
        guard !incomes.isEmpty else { return [:] }
        let taxableIncomes = incomes.filter { $0.isTaxable }
        guard !taxableIncomes.isEmpty else { return [:] }
        return distributedTaxAmounts(
            buckets: taxableIncomes.map { (key: $0.id, taxableAmount: $0.amount) },
            taxRate: taxRate
        )
    }

    /// Distributes tax for (income, effectiveMonthlyAmount) pairs using the largest-remainder method.
    /// Aggregates multiple entries for the same UUID (e.g. recurring incomes with multiple
    /// occurrences in a month), groups by effective rate, and distributes so that per-UUID taxes
    /// sum exactly to the total month tax. This is the canonical tax path for all display screens.
    /// - Returns: [UUID: Decimal] where .values.sumMoney() equals the total month tax exactly.
    static func distributedTaxAmounts(
        for pairs: [(income: Income, amount: Decimal)],
        defaultPercentage: Double
    ) -> [UUID: Decimal] {
        let taxable = pairs.filter { $0.income.isTaxable }
        guard !taxable.isEmpty else { return [:] }

        // Aggregate effective amounts by UUID (recurring incomes may appear multiple times)
        var amountByID: [UUID: Decimal] = [:]
        var incomeByID: [UUID: Income] = [:]
        for pair in taxable {
            amountByID[pair.income.id, default: 0] += pair.amount
            if incomeByID[pair.income.id] == nil { incomeByID[pair.income.id] = pair.income }
        }

        // Group by effective rate (basis points) for stable key comparison, then distribute
        let buckets = amountByID.map { id, amount in (key: id, taxableAmount: amount) }
        let groups = Dictionary(grouping: buckets) { bucket -> Int64 in
            let rate = incomeByID[bucket.key]?.effectiveTaxRate(defaultPercentage: defaultPercentage) ?? 0
            return NSDecimalNumber(decimal: (rate * 10_000).roundedMoney()).int64Value
        }
        var result: [UUID: Decimal] = [:]
        for (basisPoints, groupBuckets) in groups {
            let rate = Decimal(basisPoints) / 10_000
            let distributed = distributedTaxAmounts(buckets: groupBuckets, taxRate: rate)
            result.merge(distributed) { _, new in new }
        }
        return result
    }

    /// Distributes tax across incomes honoring per-income rate overrides.
    /// Groups by effective rate (integer basis points) for stable key comparison.
    static func distributedTaxAmounts(for incomes: [Income], defaultPercentage: Double) -> [UUID: Decimal] {
        let taxable = incomes.filter { $0.isTaxable }
        guard !taxable.isEmpty else { return [:] }
        // Group by integer basis points to avoid floating-point key instability
        let groups = Dictionary(grouping: taxable) { income -> Int64 in
            NSDecimalNumber(decimal: (income.effectiveTaxRate(defaultPercentage: defaultPercentage) * 10_000).roundedMoney()).int64Value
        }
        var result: [UUID: Decimal] = [:]
        for (basisPoints, groupIncomes) in groups {
            let rate = Decimal(basisPoints) / 10_000
            let distributed = distributedTaxAmounts(
                buckets: groupIncomes.map { (key: $0.id, taxableAmount: $0.amount) },
                taxRate: rate
            )
            result.merge(distributed) { _, new in new }
        }
        return result
    }
}

// MARK: - First-of-Month Date Helper

nonisolated extension Calendar {
    /// Returns the first day of the given month and year, or nil if the date cannot be constructed.
    func firstOfMonth(month: Int, year: Int) -> Date? {
        date(from: DateComponents(year: year, month: month, day: 1))
    }
}
