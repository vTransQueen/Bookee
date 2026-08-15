//
//  MoneyUtilities.swift
//  K Test
//
//  Created by Kara Eveland on 5/6/26.
//

import Foundation

/// Centralized utilities for handling monetary calculations with proper floating point precision
/// All financial calculations should use these methods to ensure consistent rounding behavior
///
/// # Floating Point Precision Strategy
///
/// This file implements a comprehensive strategy to handle floating point precision issues in
/// monetary calculations. The approach includes:
///
/// ## 1. Immediate Rounding
/// All monetary values are rounded to 2 decimal places (cents precision) immediately after
/// any arithmetic operation. This prevents precision errors from accumulating.
///
/// **Why this matters:** Floating point arithmetic like `0.1 + 0.2` produces `0.30000000000000004`
/// instead of `0.3`. Rounding immediately after each operation prevents these tiny errors from
/// compounding through multiple calculations.
///
/// ## 2. Tolerant Comparisons
/// Instead of direct equality checks (==), we use tolerance-based comparisons with a threshold
/// of 0.0001 (less than 0.01 cents). This handles floating point imprecision gracefully.
///
/// **Why this matters:** After complex calculations, `100.0 - 99.99` might equal `0.010000000000005116`
/// instead of exactly `0.01`. Tolerance-based comparisons treat values within 0.0001 as equal.
///
/// ## 3. Safe Summation
/// The `sumMoney()` method rounds after each addition, preventing the accumulation of tiny
/// errors that can occur when summing many values.
///
/// **Why this matters:** Summing 1000 values of `0.01` with standard addition produces
/// `10.000000000000014` instead of exactly `10.0`. Our method ensures exact `10.0`.
///
/// ## 4. Zero Normalization
/// Special handling for negative zero (-0.0) ensures consistent display and comparison behavior.
///
/// **Why this matters:** IEEE 754 floating point has both `+0.0` and `-0.0`, which can cause
/// display inconsistencies. We normalize all zeros to `+0.0`.
///
/// ## 5. Division by Zero Protection
/// The `isEffectivelyZero` check is used before division operations to prevent crashes when
/// values approach zero (e.g., when tax rate approaches 100%).
///
/// **Why this matters:** Dividing by a value very close to zero (like `0.00001`) produces
/// astronomically large numbers. Checking `isEffectivelyZero` catches these cases.
///
/// ## 6. Intermediate Value Rounding
/// Complex expressions are broken down into intermediate variables, each rounded separately,
/// to prevent precision loss through long calculation chains.
///
/// **Example:** Instead of `let result = (a + b) * c - (d / e)`, we use:
/// ```swift
/// let sum = roundMoney(a + b)
/// let product = roundMoney(sum * c)
/// let quotient = roundMoney(d / e)
/// let result = roundMoney(product - quotient)
/// ```
///
/// ## Example Usage:
/// ```swift
/// // ✅ Good: Uses rounding after calculation
/// let tax = roundMoney(income * taxRate)
///
/// // ✅ Good: Uses tolerant comparison
/// if amount.isEffectivelyZero { /* handle zero case */ }
///
/// // ✅ Good: Uses safe summation
/// let total = expenseAmounts.sumMoney()
///
/// // ✅ Good: Breaks down complex calculations
/// let sum1 = roundMoney(a + b)
/// let sum2 = roundMoney(sum1 + c)
///
/// // ❌ Bad: Direct floating point arithmetic without rounding
/// let tax = income * taxRate  // Don't do this!
///
/// // ❌ Bad: Direct equality check
/// if amount == 0.0 { /* might miss -0.00001 */ }  // Don't do this!
///
/// // ❌ Bad: Long calculation chain without intermediate rounding
/// let result = (a + b) * c - (d / e)  // Don't do this!
/// ```
extension Double {
    /// Rounds a monetary value to 2 decimal places to prevent floating point precision issues
    /// Example: 10.999999 becomes 11.00
    /// - Returns: The value rounded to 2 decimal places (cents precision)
    func roundedMoney() -> Double {
        // A tiny epsilon nudge corrects IEEE 754 representation errors at half-cent boundaries.
        // e.g. 1.005 is stored as 1.00499... and would otherwise round down to 1.00 instead of 1.01.
        // 1e-9 is ~1000× smaller than 0.5 cent so it never affects non-borderline values,
        // yet is well above the float representation error for monetary amounts up to ~$10M.
        let epsilon: Double = self >= 0 ? 1e-9 : -1e-9
        return ((self + epsilon) * 100).rounded() / 100
    }
    
    /// Checks if this value is effectively zero for monetary purposes
    /// Uses a tolerance of 0.0001 (less than 0.01 cents) to handle floating point imprecision
    /// - Returns: True if the absolute value is less than 0.0001
    var isEffectivelyZero: Bool {
        return abs(self) < 0.0001
    }
    
    /// Checks if this value is effectively negative for monetary purposes
    /// Uses a tolerance of 0.0001 to handle floating point imprecision
    /// - Returns: True if the value is less than -0.0001
    var isEffectivelyNegative: Bool {
        return self < -0.0001
    }
    
    /// Checks if this value is effectively positive for monetary purposes
    /// Uses a tolerance of 0.0001 to handle floating point imprecision
    /// - Returns: True if the value is greater than 0.0001
    var isEffectivelyPositive: Bool {
        return self > 0.0001
    }

    /// Checks if two monetary values are effectively equal within cent tolerance
    /// Use instead of `==` / `!=` to avoid false differences from float residue
    /// - Returns: True if the absolute difference is less than 0.0001
    func isEffectivelyEqual(to other: Double) -> Bool {
        return (self - other).isEffectivelyZero
    }

    /// Normalizes negative zero to positive zero for consistent display
    /// Ensures -0.0 is converted to 0.0
    /// - Returns: 0.0 if the value is -0.0, otherwise returns self
    var normalizedZero: Double {
        return self == -0.0 ? 0.0 : self
    }
    
    /// Rounds and normalizes a monetary value in one step
    /// Combines rounding to 2 decimal places with zero normalization
    /// - Returns: The rounded and normalized value
    func roundedAndNormalizedMoney() -> Double {
        let rounded = self.roundedMoney()
        // If effectively zero, return positive zero
        if rounded.isEffectivelyZero {
            return 0.0
        }
        // For non-zero values, check for negative zero edge case
        // (only possible if value is exactly -0.0 before rounding, which is rare)
        return rounded == -0.0 ? 0.0 : rounded
    }
}

/// Extension for sequences of monetary amounts with safe accumulation
extension Sequence where Element == Double {
    /// Sums monetary values with rounding after each addition to prevent accumulation errors
    /// More accurate than standard reduce for long sequences of floating point values
    /// - Returns: The sum of all values, rounded to 2 decimal places
    func sumMoney() -> Double {
        return self.reduce(0.0) { accumulator, value in
            (accumulator + value).roundedMoney()
        }.roundedMoney() // Final rounding for safety
    }
}

// MARK: - Date Utilities

extension Date {
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

/// Returns the current date formatted as "yyyy-MM-dd_HH-mm-ss" — the canonical file-safe timestamp used
/// throughout the app for photo and backup filenames.
func makeTimestamp(from date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter.string(from: date)
}

// MARK: - Photo Filename Helper

/// Generates a timestamped filename for a photo attachment (e.g. "photo_2026-06-14_09-30-00.jpg").
func makePhotoFileName() -> String {
    "photo_\(makeTimestamp()).jpg"
}

// MARK: - Month Name Helper

/// Returns the full month name for a 1-based month number (1 = January … 12 = December).
func monthDisplayName(_ month: Int) -> String {
    Calendar.current.monthSymbols[month - 1]
}

/// Legacy compatibility alias — prefer `.roundedMoney()` on new call sites.
@inline(__always)
func roundMoney(_ value: Double) -> Double {
    value.roundedMoney()
}

// MARK: - Tax Distribution Helper

/// Helper for distributing tax amounts across incomes to ensure they sum exactly to the total.
///
/// This prevents rounding errors where individual taxes might not add up to the displayed total.
///
/// Example:
/// - Income 1: $7.10 × 11% = $0.781 → rounds down to $0.78
/// - Income 2: $56.80 × 11% = $6.248 → rounds down to $6.24
/// - Total: $63.90 × 11% = $7.029 → rounds to $7.03
/// - Problem: $0.78 + $6.24 = $7.02 ✗ (off by $0.01!)
///
/// With the largest remainder method, we round all items down, then distribute the missing cents
/// to the items with the largest fractional remainders, ensuring the sum equals the total.
struct TaxDistributionHelper {
    /// Generic overload: distributes tax across arbitrary keyed buckets using the largest-remainder method.
    /// Each bucket provides a taxable amount; the algorithm ensures the sum of distributed taxes
    /// equals `roundMoney(totalTaxableAmount * taxRate)` exactly.
    /// - Parameter buckets: Array of (key, taxable amount) pairs. Items with non-positive amounts are ignored.
    /// - Parameter taxRate: Tax rate as a decimal (e.g., 0.11 for 11%). Do NOT round this value.
    /// - Returns: Dictionary mapping each key to its distributed tax amount.
    static func distributedTaxAmounts<Key: Hashable>(
        buckets: [(key: Key, taxableAmount: Double)],
        taxRate: Double
    ) -> [Key: Double] {
        let activeBuckets = buckets.filter { $0.taxableAmount.isEffectivelyPositive }
        guard !activeBuckets.isEmpty else { return [:] }

        let totalIncome = activeBuckets.map { $0.taxableAmount }.sumMoney()
        let exactTotalTax = roundMoney(totalIncome * taxRate)

        var taxData: [(key: Key, floor: Double, remainder: Double)] = activeBuckets.map { bucket in
            let amountCents = Int((bucket.taxableAmount * 100.0).rounded())
            let basisPoints = Int((taxRate * 10000.0).rounded())
            let exactCents = Double(amountCents * basisPoints) / 10000.0
            let floorCents = floor(exactCents)
            let floorTax = roundMoney(floorCents / 100.0)
            return (key: bucket.key, floor: floorTax, remainder: exactCents - floorCents)
        }

        let totalFloor = taxData.map { $0.floor }.sumMoney()
        let centsNeeded = max(0, Int((exactTotalTax * 100.0).rounded()) - Int((totalFloor * 100.0).rounded()))

        taxData.sort { $0.remainder > $1.remainder }

        var result: [Key: Double] = [:]
        for (index, data) in taxData.enumerated() {
            let adjustment = index < centsNeeded ? 0.01 : 0.0
            result[data.key] = roundMoney(data.floor + adjustment)
        }
        return result
    }

    /// Calculates distributed tax amounts for a collection of incomes using the largest remainder method.
    ///
    /// - Parameters:
    ///   - incomes: Array of Income items (nontaxable items are automatically filtered out)
    ///   - taxRate: Tax rate as a percentage decimal (e.g., 0.11 for 11%)
    /// - Returns: Dictionary mapping income IDs to their distributed tax amounts
    static func distributedTaxAmounts(for incomes: [Income], taxRate: Double) -> [UUID: Double] {
        guard !incomes.isEmpty else { return [:] }
        let taxableIncomes = incomes.filter { $0.isTaxable }
        guard !taxableIncomes.isEmpty else { return [:] }
        return distributedTaxAmounts(
            buckets: taxableIncomes.map { (key: $0.id, taxableAmount: $0.amount) },
            taxRate: taxRate
        )
    }
}

// MARK: - Tax Amount Helper

extension Double {
    /// Calculates the tax amount for this monetary value at the given rate, rounded to cents.
    /// Use for tax-amount formulas only (e.g. income * taxRate → tax due).
    /// Do NOT use for the income-needed divisor (1 - taxRate) — that must stay at full precision.
    func taxAmount(rate: Double) -> Double {
        roundMoney(self * rate)
    }
}

// MARK: - Floor Cents Per Payment

/// Calculates the per-payment amount for a payment plan using floor (cents-down) division.
/// Both Expense.largestRemainderBase (Models.swift) and calculatePaymentAmount (AddEditViews.swift)
/// delegate to this single implementation to ensure consistent behavior.
/// - Returns: nil if total is not positive or payments is zero.
func floorCentsPerPayment(total: Double, payments: Int) -> Double? {
    guard total.isEffectivelyPositive, payments > 0 else { return nil }
    let totalCents = Int((total.roundedMoney() * 100.0).rounded())
    let centsPerPayment = totalCents / payments
    return roundMoney(Double(centsPerPayment) / 100.0)
}

// MARK: - First-of-Month Date Helper

extension Calendar {
    /// Returns the first day of the given month and year, or nil if the date cannot be constructed.
    func firstOfMonth(month: Int, year: Int) -> Date? {
        date(from: DateComponents(year: year, month: month, day: 1))
    }
}
