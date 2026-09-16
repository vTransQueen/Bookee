//
//  BookeeTests.swift
//  BookeeTests
//
//  Created by Kara Eveland on 2/14/26.
//

import Testing
import Foundation
import CoreGraphics
@testable import Bookee

// MARK: - Floating Point Precision Tests
@Suite("Floating Point Precision Tests")
struct FloatingPointPrecisionTests {
    
    // MARK: - Money Rounding Tests
    
    @Test("Rounding to 2 decimal places")
    func testMoneyRounding() {
        // Test standard rounding
        #expect(10.999.roundedMoney() == 11.0)
        #expect(10.994.roundedMoney() == 10.99)
        #expect(10.995.roundedMoney() == 11.0)
        #expect(10.001.roundedMoney() == 10.0)
        
        // Test edge cases
        #expect(0.0.roundedMoney() == 0.0)
        #expect((-0.0).roundedMoney() == 0.0)
        #expect(0.004.roundedMoney() == 0.0)
        #expect(0.005.roundedMoney() == 0.01)
    }
    
    @Test("Sum of many small amounts")
    func testSumOfManySmallAmounts() {
        // Create array of 1000 small amounts (0.01 each)
        let amounts = Array(repeating: 0.01, count: 1000)
        let sum = amounts.sumMoney()
        
        // Should equal exactly $10.00
        #expect(sum == 10.0)
        #expect(sum.isEffectivelyZero == false)
        
        // Test with slightly imprecise values
        let impreciseAmounts = Array(repeating: 0.0099999999, count: 100)
        let impreciseSum = impreciseAmounts.sumMoney()
        
        // Should round to $1.00
        #expect(impreciseSum == 1.0)
    }
    
    @Test("Sum with accumulation errors")
    func testSumWithAccumulationErrors() {
        // Classic floating point issue: 0.1 + 0.2 != 0.3
        let amounts = [0.1, 0.2]
        let sum = amounts.sumMoney()
        
        #expect(sum == 0.3)
        
        // Test larger accumulation
        let repeatedAmounts = Array(repeating: 0.1, count: 10)
        let repeatedSum = repeatedAmounts.sumMoney()
        
        #expect(repeatedSum == 1.0)
    }
    
    // MARK: - Zero Comparison Tests
    
    @Test("Effective zero detection")
    func testEffectiveZeroDetection() {
        #expect(0.0.isEffectivelyZero == true)
        #expect((-0.0).isEffectivelyZero == true)
        #expect(0.00001.isEffectivelyZero == true)
        #expect((-0.00001).isEffectivelyZero == true)
        #expect(0.0001.isEffectivelyZero == false)
        #expect(0.01.isEffectivelyZero == false)
    }
    
    @Test("Effective positive detection")
    func testEffectivePositiveDetection() {
        #expect(0.01.isEffectivelyPositive == true)
        #expect(0.0001.isEffectivelyPositive == false)  // 0.0001 > 0.0001 is false (strict threshold)
        #expect(0.00001.isEffectivelyPositive == false)
        #expect(0.0.isEffectivelyPositive == false)
        #expect((-0.01).isEffectivelyPositive == false)
    }
    
    @Test("Effective negative detection")
    func testEffectiveNegativeDetection() {
        #expect((-0.01).isEffectivelyNegative == true)
        #expect((-0.0001).isEffectivelyNegative == false)  // -0.0001 < -0.0001 is false (strict threshold)
        #expect((-0.00001).isEffectivelyNegative == false)
        #expect(0.0.isEffectivelyNegative == false)
        #expect(0.01.isEffectivelyNegative == false)
    }
    
    @Test("Negative zero normalization")
    func testNegativeZeroNormalization() {
        let negativeZero = -0.0
        #expect(negativeZero.normalizedZero == 0.0)
        #expect(0.0.normalizedZero == 0.0)
        #expect(0.01.normalizedZero == 0.01)
        #expect((-0.01).normalizedZero == -0.01)
    }
    
    // MARK: - Tax Calculation Tests
    
    @Test("Tax calculations with extreme percentages")
    func testTaxCalculationsExtremePercentages() {
        // Test very low tax rate (0.01%)
        let income1 = 10000.0
        let taxRate1 = 0.0001 // 0.01%
        let tax1 = roundMoney(income1 * taxRate1)
        #expect(tax1 == 1.0)
        
        // Test very high tax rate (99.99%)
        let income2 = 10000.0
        let taxRate2 = 0.9999 // 99.99%
        let tax2 = roundMoney(income2 * taxRate2)
        #expect(tax2 == 9999.0)
        
        // Test standard tax rate (11%)
        let income3 = 100.0
        let taxRate3 = 0.11
        let tax3 = roundMoney(income3 * taxRate3)
        #expect(tax3 == 11.0)
    }
    
    @Test("Tax rate approaching 100%")
    func testTaxRateApproaching100Percent() {
        // Rates must NOT be rounded to 2dp — they are multipliers, not money amounts.
        // 99.99 / 100 = 0.9999 (approx), so divisor = 1 - 0.9999 ≈ 0.0001, not zero.
        let taxRate = 99.99 / 100.0
        let divisor = 1.0 - taxRate
        
        // Should not be effectively zero
        #expect(!divisor.isEffectivelyZero)
        
        // Test at exactly 100%
        let taxRate100 = 100.0 / 100.0
        let divisor100 = 1.0 - taxRate100
        
        // Should be effectively zero
        #expect(divisor100.isEffectivelyZero)
        
        // Fractional percentage test: 11.5% must NOT be corrupted to 11% by rounding.
        let taxRate11_5 = 11.5 / 100.0
        let divisor11_5 = 1.0 - taxRate11_5
        let taxableIncomeNeeded = roundMoney(100.0 / divisor11_5)
        // 100 / 0.885 ≈ $112.99; tax ≈ $12.99; after tax ≈ $100.00
        let afterTax = roundMoney(taxableIncomeNeeded - roundMoney(taxableIncomeNeeded * taxRate11_5))
        #expect(afterTax == 100.0)
    }
    
    @Test("Tax calculation with division")
    func testTaxCalculationWithDivision() {
        // Testing: taxable income needed = expenses / (1 - taxRate)
        // Divisors must NOT be rounded to 2dp — that would shift the result.
        let expenses = 100.0
        let taxRate = 0.11
        let divisor = 1.0 - taxRate
        
        guard !divisor.isEffectivelyZero else {
            Issue.record("Divisor should not be zero for 11% tax rate")
            return
        }
        
        let taxableIncomeNeeded = roundMoney(expenses / divisor)
        let expectedTax = roundMoney(taxableIncomeNeeded * taxRate)
        
        // After-tax amount should equal expenses
        let afterTax = roundMoney(taxableIncomeNeeded - expectedTax)
        #expect(afterTax == expenses)
    }
    
    // MARK: - Frequency Multiplier Tests
    
    @Test("Bi-weekly frequency multiplier")
    func testBiweeklyFrequencyMultiplier() {
        let weeksPerMonth = 4.0
        let biweeklyMultiplier = (weeksPerMonth / 2.0).roundedMoney()
        #expect(biweeklyMultiplier == 2.0)
        
        // Test with decimal weeks
        let weeksPerMonth2 = 4.33
        let biweeklyMultiplier2 = (weeksPerMonth2 / 2.0).roundedMoney()
        #expect(biweeklyMultiplier2 == 2.17)
    }
    
    @Test("Quarterly frequency multiplier")
    func testQuarterlyFrequencyMultiplier() {
        let quarterlyMultiplier = (1.0 / 3.0).roundedMoney()
        #expect(quarterlyMultiplier == 0.33)
        
        // Test that 3 months worth equals close to the base amount.
        // Note: 1/3 rounds down to 0.33, so each payment loses ~0.00333 per dollar.
        // For $99: 99 × (1/3 - 0.33) × 3 ≈ $0.99 total shortfall — nearly 1% of the base.
        let monthlyAmount = 99.0
        let quarterlyAmount = roundMoney(monthlyAmount * quarterlyMultiplier)
        let threeMonths = roundMoney(quarterlyAmount * 3.0)
        
        let difference = abs(threeMonths - monthlyAmount)
        #expect(difference <= 1.00) // ~0.99: rounding 1/3 → 0.33 loses ≈1% of monthlyAmount
    }
    
    @Test("Yearly frequency multiplier")
    func testYearlyFrequencyMultiplier() {
        let yearlyMultiplier = (1.0 / 12.0).roundedMoney()
        #expect(yearlyMultiplier == 0.08)
        
        // Test that 12 months worth is close to the base amount.
        // Note: 1/12 rounds down to 0.08, so each payment loses ~0.00333 per dollar.
        // For $1200: 1200 × (1/12 - 0.08) × 12 ≈ $48 total shortfall — 4% of the base.
        let monthlyAmount = 1200.0
        let yearlyAmount = roundMoney(monthlyAmount * yearlyMultiplier)
        let twelveMonths = roundMoney(yearlyAmount * 12.0)
        
        let difference = abs(twelveMonths - monthlyAmount)
        #expect(difference <= 50.00) // ~48.0: rounding 1/12 → 0.08 loses ≈4% of monthlyAmount
    }
    
    @Test("Weeks per month calculation")
    func testWeeksPerMonthCalculation() {
        // Standard 52 weeks per year
        let weeksPerMonth = (52.0 / 12.0).roundedMoney()
        #expect(weeksPerMonth == 4.33)
        
        // For a specific 30-day month
        let daysInMonth = 30.0
        let weeksInMonth = (daysInMonth / 7.0).roundedMoney()
        #expect(weeksInMonth == 4.29)
    }
    
    // MARK: - Payment Plan Tests
    
    @Test("Payment plan with odd total")
    func testPaymentPlanWithOddTotal() {
        // $100.01 over 3 months using largest remainder method
        let total = 100.01
        let monthCount = 3.0
        
        // Round total first to ensure consistency
        let totalRounded = total.roundedMoney()
        
        // Convert to cents with proper rounding
        let totalCents = roundMoney(totalRounded * 100.0)
        
        // Calculate cents per month with floor division
        let centsPerMonthRaw = roundMoney(totalCents / monthCount)
        let centsPerMonth = floor(centsPerMonthRaw)
        
        // Convert back to dollars
        let baseAmount = roundMoney(centsPerMonth / 100.0)
        
        // Calculate total base and remainder
        let baseAmountTimesCount = roundMoney(baseAmount * monthCount)
        let totalBase = baseAmountTimesCount.roundedMoney()
        let difference = roundMoney(totalRounded - totalBase)
        let remainder = difference.roundedMoney()
        let remainderCents = roundMoney(remainder * 100.0)
        let centsNeeded = Int(remainderCents)
        
        // Base amount should be $33.33
        #expect(baseAmount == 33.33)
        
        // Total of base amounts: $99.99
        #expect(totalBase == 99.99)
        
        // Remainder: $0.02
        #expect(remainder == 0.02)
        
        // 2 cents needed, so 2 payments get an extra cent
        #expect(centsNeeded == 2)
        
        // First 2 payments: $33.34, Last payment: $33.33
        let payment1 = roundMoney(baseAmount + 0.01)
        let payment2 = roundMoney(baseAmount + 0.01)
        let payment3 = baseAmount.roundedMoney()
        
        #expect(payment1 == 33.34)
        #expect(payment2 == 33.34)
        #expect(payment3 == 33.33)
        
        // Sum should equal exactly the total
        let sum1 = roundMoney(payment1 + payment2)
        let sumOfPayments = roundMoney(sum1 + payment3)
        #expect(sumOfPayments == total)
    }
    
    @Test("Payment plan ensures exact sum")
    func testPaymentPlanExactSum() {
        // Test various totals to ensure they always sum correctly
        let testCases: [(total: Double, months: Int)] = [
            (100.00, 3),
            (100.01, 3),
            (100.99, 3),
            (1000.00, 12),
            (1000.17, 12),
            (99.99, 7)
        ]
        
        for testCase in testCases {
            let total = testCase.total
            let monthCount = Double(testCase.months)
            
            // Round total first
            let totalRounded = total.roundedMoney()
            
            // Convert to cents with proper rounding
            let totalCents = roundMoney(totalRounded * 100.0)
            
            // Calculate cents per month with floor division
            let centsPerMonthRaw = roundMoney(totalCents / monthCount)
            let centsPerMonth = floor(centsPerMonthRaw)
            
            // Convert back to dollars
            let baseAmount = roundMoney(centsPerMonth / 100.0)
            
            // Calculate total base and remainder
            let baseAmountTimesCount = roundMoney(baseAmount * monthCount)
            let totalBase = baseAmountTimesCount.roundedMoney()
            let difference = roundMoney(totalRounded - totalBase)
            let remainder = difference.roundedMoney()
            let remainderCents = roundMoney(remainder * 100.0)
            let centsNeeded = Int(remainderCents)
            
            // Calculate sum of all payments
            var sum = 0.0
            for i in 1...testCase.months {
                let extraCent = i <= centsNeeded ? 0.01 : 0.0
                let payment = roundMoney(baseAmount + extraCent)
                sum = roundMoney(sum + payment)
            }
            
            #expect(sum == total, "For total \(total) over \(testCase.months) months, sum should equal total")
        }
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Very small amounts don't disappear")
    func testVerySmallAmountsDontDisappear() {
        let smallAmount = 0.01
        let rounded = smallAmount.roundedMoney()
        #expect(rounded == 0.01)
        #expect(!rounded.isEffectivelyZero)
    }
    
    @Test("Very large numbers maintain precision")
    func testVeryLargeNumbersPrecision() {
        let largeAmount = 999999.99
        let rounded = largeAmount.roundedMoney()
        #expect(rounded == 999999.99)
        
        // Test addition
        let sum = (largeAmount + 0.01).roundedMoney()
        #expect(sum == 1000000.0)
    }
    
    @Test("Repeated operations maintain precision")
    func testRepeatedOperationsPrecision() {
        var amount = 100.0
        
        // Subtract 0.01 one hundred times
        for _ in 1...100 {
            amount = (amount - 0.01).roundedMoney()
        }
        
        // Should equal exactly 99.00
        #expect(amount == 99.0)
    }
    
    @Test("Mixed positive and negative amounts")
    func testMixedPositiveNegativeAmounts() {
        let amounts = [100.0, -50.0, 25.0, -25.0, 10.0]
        let sum = amounts.sumMoney()
        
        #expect(sum == 60.0)
        
        // Test with very small differences
        let amounts2 = [0.01, -0.01, 0.01, -0.01, 0.01]
        let sum2 = amounts2.sumMoney()
        
        #expect(sum2 == 0.01)
    }
}

// MARK: - Tax Distribution Tests
@Suite("Tax Distribution Precision Tests")
struct TaxDistributionTests {

    // Helpers to build exact Decimal income amounts.
    private func income(_ name: String, _ amountStr: String, taxable: Bool = true) -> Income {
        Income(name: name, amount: Decimal(string: amountStr)!,
               date: Date(), isRecurring: false, recurringFrequency: .monthly, isTaxable: taxable)
    }
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    @Test("Tax distribution example from documentation — exact Decimal inputs")
    func testTaxDistributionDocExample() {
        // Income 1: $7.10 × 11% = $0.781 → floor $0.78, remainder 0.1
        // Income 2: $56.80 × 11% = $6.248 → floor $6.24, remainder 8
        // Total: $63.90 × 11% = $7.029 → rounds to $7.03
        // Naïve sum: $0.78 + $6.24 = $7.02 ✗ — largest-remainder adds $0.01 to income 2
        let i1 = income("Income 1", "7.10")
        let i2 = income("Income 2", "56.80")
        let taxRate = d("0.11")

        let distributed = TaxDistributionHelper.distributedTaxAmounts(for: [i1, i2], taxRate: taxRate)

        let tax1 = distributed[i1.id] ?? 0
        let tax2 = distributed[i2.id] ?? 0

        // Expected total: roundMoney(63.90 × 0.11) = roundMoney(7.029) = 7.03
        let totalIncome = [i1.amount, i2.amount].sumMoney()
        let expectedTotal = roundMoney(totalIncome * taxRate)
        #expect(expectedTotal == d("7.03"), "Total tax should be exactly $7.03")

        // Sum of distributed must equal total — exact, no tolerance
        let sumOfDistributed = [tax1, tax2].sumMoney()
        #expect(sumOfDistributed == expectedTotal,
                "Distributed taxes \(sumOfDistributed) must equal \(expectedTotal) exactly")

        // Specific allocation: income 2 gets the extra cent (largest remainder)
        #expect(tax1 == d("0.78"))
        #expect(tax2 == d("6.25"))
    }

    @Test("Tax distribution with many small incomes — exact sum")
    func testTaxDistributionManySmallIncomes() {
        let incomes = (1...100).map { i in income("Income \(i)", "1.01") }
        let taxRate = d("0.11")

        let distributed = TaxDistributionHelper.distributedTaxAmounts(for: incomes, taxRate: taxRate)

        let totalIncome = incomes.map { $0.amount }.sumMoney()
        let expectedTotal = roundMoney(totalIncome * taxRate)
        let sumOfDistributed = distributed.values.reduce(Decimal(0)) { $0 + $1 }.roundedMoney()

        #expect(sumOfDistributed == expectedTotal,
                "Sum of distributed taxes must equal total exactly, no tolerance")
    }

    @Test("Tax distribution filters nontaxable incomes")
    func testTaxDistributionFiltersNontaxable() {
        let taxable    = income("Taxable",    "100.00", taxable: true)
        let nontaxable = income("Nontaxable", "50.00",  taxable: false)
        let taxRate = d("0.11")

        let distributed = TaxDistributionHelper.distributedTaxAmounts(for: [taxable, nontaxable], taxRate: taxRate)

        #expect(distributed.count == 1)
        #expect(distributed[taxable.id]    != nil)
        #expect(distributed[nontaxable.id] == nil)
        #expect(distributed[taxable.id]    == roundMoney(d("100.00") * taxRate))
    }

    @Test("Tax distribution with zero tax rate")
    func testTaxDistributionZeroRate() {
        let i1 = income("Income 1", "100.00")
        let i2 = income("Income 2", "200.00")

        let distributed = TaxDistributionHelper.distributedTaxAmounts(for: [i1, i2], taxRate: 0)

        #expect(distributed[i1.id] == 0)
        #expect(distributed[i2.id] == 0)
    }

    @Test("Tax distribution with 99.99% rate — exact $99.99 on $100")
    func testTaxDistributionHighRate() {
        let inc = income("Income", "100.00")
        let taxRate = d("0.9999")

        let distributed = TaxDistributionHelper.distributedTaxAmounts(for: [inc], taxRate: taxRate)

        let tax = distributed[inc.id] ?? 0
        #expect(tax == d("99.99"))
    }

    @Test("Per-income rounding: sum of months equals year total")
    func testPerIncomeTaxRoundingMatchesYearView() {
        // Two $1.50 one-time incomes at 11%.
        // Per-income: roundMoney(1.50 × 0.11) = roundMoney(0.165) = $0.17 each → sum $0.34.
        // Group-then-round: roundMoney(3.00 × 0.11) = roundMoney(0.33) = $0.33 — different!
        // The year overview uses per-income rounding; month view must match.
        let rate = d("0.11")
        let yearViewMethod = [roundMoney(d("1.50") * rate), roundMoney(d("1.50") * rate)].sumMoney()
        #expect(yearViewMethod == d("0.34"),
                "Per-income rounding: two $1.50 × 11% must be $0.34")

        // groupTotal × rate gives a different answer — this is intentional and documented.
        let groupMethod = roundMoney(d("3.00") * rate)
        #expect(groupMethod == d("0.33"),
                "Group-then-round gives $0.33, which does NOT match the year overview")
        #expect(yearViewMethod != groupMethod,
                "The two methods differ by $0.01; month view must use per-income rounding")
    }

    @Test("Tax total for expanded recurring income (multi-occurrence same UUID)")
    func testTaxTotalMultiOccurrenceSameUUID() {
        // A bi-weekly $1000 income taxed at 25% appears twice in a month.
        // expandedIncomes has two Income objects with the SAME UUID.
        // Per-income aggregation: aggregate $1000+$1000=$2000 by UUID, then roundMoney(2000×0.25)=$500.
        // distributedTaxAmounts (UUID-keyed dict) would give $250 (last-wins) — that is the bug.
        let base = Income(name: "Biweekly Pay", amount: d("1000.00"),
                          date: Date(), isRecurring: true,
                          recurringFrequency: .biweekly, isTaxable: true)
        var occ2 = base
        occ2.date = Calendar.current.date(byAdding: .day, value: 14, to: base.date) ?? base.date

        // Simulate the per-income aggregation used by calendarMonthTaxSavings:
        var amountByID: [UUID: Decimal] = [:]
        for occ in [base, occ2] where occ.isTaxable {
            amountByID[occ.id, default: 0] += occ.amount
        }
        let aggregatedTax = amountByID.map { _, amount in
            roundMoney(amount * d("0.25"))
        }.sumMoney()
        #expect(aggregatedTax == d("500.00"),
                "Two $1000 occurrences at 25% must produce $500 tax, not $250")
    }

    @Test("Tax distribution with odd amounts — all results rounded, sum exact")
    func testTaxDistributionOddAmounts() {
        let i1 = income("Income 1", "7.13")
        let i2 = income("Income 2", "19.87")
        let i3 = income("Income 3", "42.99")
        let taxRate = d("0.073")

        let distributed = TaxDistributionHelper.distributedTaxAmounts(for: [i1, i2, i3], taxRate: taxRate)

        let totalIncome = [i1, i2, i3].map { $0.amount }.sumMoney()
        let expectedTotal = roundMoney(totalIncome * taxRate)
        let sumOfDistributed = distributed.values.reduce(Decimal(0)) { $0 + $1 }.roundedMoney()

        #expect(sumOfDistributed == expectedTotal,
                "Distributed amounts \(sumOfDistributed) must equal expected \(expectedTotal)")

        for (_, amount) in distributed {
            #expect(amount == amount.roundedMoney(),
                    "Each distributed amount must already be rounded to 2dp")
        }
    }
}

// MARK: - Color Conversion Tests
@Suite("Color Conversion Precision Tests")
struct ColorConversionTests {
    
    @Test("RGB to hex conversion uses proper rounding")
    func testRGBToHexConversion() {
        // Test that values are properly rounded to nearest integer
        // This is harder to test directly without UIColor, but we can verify the logic
        
        // Test edge cases in the conversion math
        let testValues: [CGFloat] = [0.0, 0.5, 0.999, 1.0, 0.001, 0.499, 0.501]
        
        for value in testValues {
            let scaled = (value * 255.0).rounded()
            let clamped = Int(max(0, min(255, scaled)))
            
            // Verify clamping works correctly
            #expect(clamped >= 0)
            #expect(clamped <= 255)
            
            // Verify rounding works as expected
            if value == 0.0 {
                #expect(clamped == 0)
            } else if value == 1.0 {
                #expect(clamped == 255)
            } else if value == 0.5 {
                #expect(clamped == 128) // 0.5 * 255 = 127.5 → 128
            }
        }
    }
    
    @Test("Hex string format is correct")
    func testHexStringFormat() {
        // Test various RGB integer values produce correct hex
        let testCases: [(r: Int, g: Int, b: Int, expected: String)] = [
            (0, 0, 0, "000000"),
            (255, 255, 255, "FFFFFF"),
            (0, 122, 255, "007AFF"), // iOS blue
            (255, 0, 0, "FF0000"),
            (0, 255, 0, "00FF00"),
            (0, 0, 255, "0000FF")
        ]

        for testCase in testCases {
            let hexString = String(format: "%02X%02X%02X", testCase.r, testCase.g, testCase.b)
            #expect(hexString == testCase.expected)
        }
    }
}

// MARK: - Money Precision Hardening Tests
@Suite("Money Precision Hardening Tests")
struct MoneyPrecisionHardeningTests {

    // MARK: - roundedMoney() boundary cases

    @Test("Half-cent boundaries for positive values round up")
    func testHalfCentBoundariesPositive() {
        #expect(1.005.roundedMoney() == 1.01)
        #expect(2.675.roundedMoney() == 2.68)
        #expect(99.995.roundedMoney() == 100.0)
        #expect(0.005.roundedMoney() == 0.01)
    }

    @Test("Half-cent boundaries for negative values round away from zero")
    func testHalfCentBoundariesNegative() {
        #expect((-1.005).roundedMoney() == -1.01)
        #expect((-2.675).roundedMoney() == -2.68)
        #expect((-0.005).roundedMoney() == -0.01)
    }

    @Test("Large magnitudes stay cent-correct at realistic amounts")
    func testLargeMagnitudePrecision() {
        let large = 9_999_999.99
        #expect(large.roundedMoney() == 9_999_999.99)
        #expect((large + 0.01).roundedMoney() == 10_000_000.0)
        #expect(1_234_567.89.roundedMoney() == 1_234_567.89)
    }

    @Test("roundedMoney is idempotent")
    func testRoundedMoneyIdempotent() {
        let values: [Double] = [0.0, 1.0, 1.005, 99.99, 100.0, -5.55, 1234.56, 0.01]
        for v in values {
            let once = v.roundedMoney()
            let twice = once.roundedMoney()
            #expect(once == twice, "roundedMoney() must be idempotent for \(v): \(once) → \(twice)")
        }
    }

    // MARK: - floorCentsPerPayment (Decimal — production overload)

    @Test("floorCentsPerPayment Decimal — exact division")
    func testFloorCentsDecimalExact() {
        let result = floorCentsPerPayment(total: Decimal(string: "90.00")!, payments: 3)
        #expect(result == Decimal(string: "30.00")!)
    }

    @Test("floorCentsPerPayment Decimal — floors uneven division")
    func testFloorCentsDecimalFloors() {
        // $100.01 / 3 = 33.3366… → floor to $33.33
        let result = floorCentsPerPayment(total: Decimal(string: "100.01")!, payments: 3)
        #expect(result == Decimal(string: "33.33")!)
    }

    @Test("floorCentsPerPayment Decimal — single payment returns exact total")
    func testFloorCentsDecimalSingle() {
        let result = floorCentsPerPayment(total: Decimal(string: "47.99")!, payments: 1)
        #expect(result == Decimal(string: "47.99")!)
    }

    @Test("floorCentsPerPayment Decimal — nil for non-positive or zero payments")
    func testFloorCentsDecimalNil() {
        #expect(floorCentsPerPayment(total: Decimal(0), payments: 3) == nil)
        #expect(floorCentsPerPayment(total: Decimal(string: "-5.00")!, payments: 3) == nil)
        #expect(floorCentsPerPayment(total: Decimal(string: "100.00")!, payments: 0) == nil)
    }

    @Test("Payment plan splits sum exactly to total — Decimal largest-remainder")
    func testDecimalPaymentPlanSumsToTotal() {
        let cases: [(totalStr: String, payments: Int)] = [
            ("100.01", 3), ("99.99", 7), ("1000.17", 12), ("7.13", 4), ("10.01", 7)
        ]
        for c in cases {
            let total = Decimal(string: c.totalStr)!
            guard let base = floorCentsPerPayment(total: total, payments: c.payments) else {
                Issue.record("nil for \(c.totalStr) / \(c.payments)")
                continue
            }
            let totalCents  = NSDecimalNumber(decimal: total * 100).intValue
            let baseCents   = NSDecimalNumber(decimal: base * 100).intValue
            let centsNeeded = totalCents - baseCents * c.payments
            let oneCent     = Decimal(1) / 100
            var sum: Decimal = 0
            for i in 1...c.payments {
                sum = roundMoney(sum + roundMoney(base + (i <= centsNeeded ? oneCent : 0)))
            }
            #expect(sum == total,
                    "Payments for \(c.totalStr)/\(c.payments) must sum to total exactly, got \(sum)")
        }
    }

    // MARK: - taxAmount(rate:) — Decimal

    @Test("Decimal taxAmount rounds multiplication result to cents")
    func testDecimalTaxAmountRounds() {
        // 7.13 × 7.3% = 0.52049 → rounds to 0.52
        #expect(Decimal(string: "7.13")!.taxAmount(rate: Decimal(string: "0.073")!) == Decimal(string: "0.52")!)
        // 100.00 × 11% = 11.00 exactly
        #expect(Decimal(string: "100.00")!.taxAmount(rate: Decimal(string: "0.11")!) == Decimal(string: "11.00")!)
        // 0.01 × 99.99% = 0.009999 → rounds to 0.01
        #expect(Decimal(string: "0.01")!.taxAmount(rate: Decimal(string: "0.9999")!) == Decimal(string: "0.01")!)
    }

    // MARK: - isEffectivelyEqual(to:)

    @Test("isEffectivelyEqual treats values within 0.0001 as equal")
    func testIsEffectivelyEqual() {
        #expect((10.0).isEffectivelyEqual(to: 10.0))
        #expect((10.00005).isEffectivelyEqual(to: 10.0))
        #expect(!(10.0001).isEffectivelyEqual(to: 10.0))
        #expect(!(10.01).isEffectivelyEqual(to: 10.0))
        // Typical floating-point residue after subtraction
        let residue = 100.0 - 99.99 // 0.010000000000005116
        #expect(residue.isEffectivelyEqual(to: 0.01))
    }

    // MARK: - roundedAndNormalizedMoney()

    @Test("roundedAndNormalizedMoney collapses near-zero to exactly 0.0")
    func testRoundedAndNormalizedMoney() {
        #expect((-0.0).roundedAndNormalizedMoney() == 0.0)
        #expect((0.00001).roundedAndNormalizedMoney() == 0.0)
        #expect((-0.00001).roundedAndNormalizedMoney() == 0.0)
        #expect((1.005).roundedAndNormalizedMoney() == 1.01)
        #expect((-5.55).roundedAndNormalizedMoney() == -5.55)
    }

    // MARK: - PercentageFormatter.formatForTextField

    @Test("formatForTextField strips trailing zeros correctly")
    func testFormatForTextFieldTrailingZeros() {
        #expect(PercentageFormatter.formatForTextField(11.0)  == "11")
        #expect(PercentageFormatter.formatForTextField(100.0) == "100")
        #expect(PercentageFormatter.formatForTextField(0.0)   == "0")
        #expect(PercentageFormatter.formatForTextField(11.5)  == "11.5")
        #expect(PercentageFormatter.formatForTextField(2.1)   == "2.1")
        #expect(PercentageFormatter.formatForTextField(11.55) == "11.55")
        #expect(PercentageFormatter.formatForTextField(7.73)  == "7.73")
    }

    @Test("formatForTextField does not corrupt 11.55 to 11.6")
    func testFormatForTextFieldNoTruncation() {
        let result = PercentageFormatter.formatForTextField(11.55)
        #expect(result == "11.55")
        #expect(result != "11.6")
    }
}

// MARK: - Decimal Money Tests
/// Tests verifying the Decimal money layer: exact representation, round-trip persistence,
/// divisor boundary, and that tax rates are never rounded to 2dp.
@Suite("Decimal Money Precision Tests")
struct DecimalMoneyTests {

    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: - Decimal roundedMoney — half-cent exactness

    @Test("Decimal 1.005 rounds up exactly — no epsilon needed")
    func testDecimalHalfCentExact() {
        // Decimal represents 1.005 exactly; no epsilon nudge required.
        #expect(d("1.005").roundedMoney() == d("1.01"))
        #expect(d("2.675").roundedMoney() == d("2.68"))
        #expect(d("99.995").roundedMoney() == d("100.00"))
        #expect(d("-1.005").roundedMoney() == d("-1.01")) // away from zero
    }

    @Test("Decimal roundedMoney is idempotent")
    func testDecimalRoundedMoneyIdempotent() {
        let values = ["0.00", "1.00", "1.005", "99.99", "100.00", "-5.55", "1234.56", "0.01"]
        for s in values {
            let v = d(s)
            #expect(v.roundedMoney() == v.roundedMoney().roundedMoney(),
                    "roundedMoney() must be idempotent for \(s)")
        }
    }

    // MARK: - Decimal sumMoney — exact accumulation

    @Test("Sum of 1000 × $0.01 is exactly $10.00 — no accumulation error")
    func testDecimalSumExact() {
        let amounts = Array(repeating: d("0.01"), count: 1000)
        #expect(amounts.sumMoney() == Decimal(10), "1000 × $0.01 must equal $10.00 exactly")
    }

    @Test("Sum of [0.1, 0.2] is exactly 0.30 — classic FP case")
    func testDecimalSumClassicCase() {
        #expect([d("0.1"), d("0.2")].sumMoney() == d("0.30"))
    }

    // MARK: - decodeMoney backward compat

    @Test("decodeMoney cleans legacy Double JSON values to exact 2dp Decimals")
    func testDecodeMoneyCleansLegacyDoubles() throws {
        struct Wrapper: Decodable {
            let amount: Decimal
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                amount = try c.decodeMoney(forKey: .amount)
            }
            enum CodingKeys: String, CodingKey { case amount }
        }
        // Simulate old JSON where 12.5 was stored as a Double.
        // Decimal(Double(12.5)) would be 12.4999... but decodeMoney must clean it.
        func decode(_ jsonStr: String) throws -> Decimal {
            let data = jsonStr.data(using: .utf8)!
            return try JSONDecoder().decode(Wrapper.self, from: data).amount
        }
        #expect(try decode("{\"amount\": 12.5}")   == d("12.50"))
        #expect(try decode("{\"amount\": 0.1}")    == d("0.10"))
        #expect(try decode("{\"amount\": 9999.99}") == d("9999.99"))
        #expect(try decode("{\"amount\": 0.0}")    == d("0.00"))
    }

    // MARK: - Tax rate divisor boundary

    @Test("Item.taxRate at 99.99% yields exactly 0.0001 — divisor == 0 guard works cleanly")
    func testTaxRateDivisorBoundary() {
        let item = Item(timestamp: Date(), name: "Test", taxSavingsPercentage: 99.99)
        let divisor = 1 - item.taxRate
        // With Decimal: 99.99/100 = 0.9999 exactly; 1 - 0.9999 = 0.0001 exactly
        #expect(divisor == d("0.0001"), "Divisor at 99.99% must be exactly 0.0001")
        #expect(divisor != 0, "99.99% must NOT trigger the divide-by-zero guard")

        let item100 = Item(timestamp: Date(), name: "Test100", taxSavingsPercentage: 100.0)
        let divisor100 = 1 - item100.taxRate
        #expect(divisor100 == 0, "100% tax must yield divisor == 0 exactly")
    }

    @Test("Tax rate at 11.5% is exactly 0.115 — NOT rounded to 0.12")
    func testTaxRateNotRounded() {
        // Tax rates are multipliers; rounding 0.115 to 0.12 would corrupt 11.5%
        let item = Item(timestamp: Date(), name: "Test", taxSavingsPercentage: 11.5)
        #expect(item.taxRate == d("0.115"), "11.5% must be 0.115, not 0.12")
    }

    // MARK: - effectiveTaxRate NOT rounded

    @Test("Income.effectiveTaxRate with 11.5% override is exactly 0.115")
    func testEffectiveTaxRateNotRounded() {
        let inc = Income(name: "Test", amount: d("100.00"), date: Date(),
                         isRecurring: false, recurringFrequency: .monthly,
                         taxPercentageOverride: d("11.5"))
        let rate = inc.effectiveTaxRate(defaultPercentage: 0)
        #expect(rate == d("0.115"),
                "11.5% override must produce 0.115, not 0.12 (which rounding to 2dp would give)")
        // Ensure $100 × 0.115 rounds to $11.50 correctly
        #expect(roundMoney(d("100.00") * rate) == d("11.50"))
    }

    // MARK: - Income-needed divisor arithmetic (banking accuracy test)

    @Test("Income needed formula is accurate to the cent at common tax rates")
    func testIncomeNeededAccuracy() {
        // At 11%: expenses $100 → needed taxable income = 100 / 0.89 ≈ $112.36
        // After 11% tax on $112.36 ($12.36) → net = $100.00
        let expenses = d("100.00")
        let rate = d("0.11")
        let divisor = 1 - rate
        let needed = roundMoney(expenses / divisor)
        let tax = roundMoney(needed * rate)
        let afterTax = roundMoney(needed - tax)
        #expect(afterTax == expenses,
                "After-tax of income-needed amount must equal expenses exactly; got \(afterTax)")
    }
}

// MARK: - Month Data Cache Header Total Tests
/// Verifies `buildMonthData` (BudgetPageView's precomputed-cache builder, now off the main actor)
/// against an independent re-derivation of the pre-refactor MonthPageView header formulas
/// (Total Excess/Needed, tax split, income/expense sums). Correctness here is the real risk of
/// precomputing these values off the main thread — the largest-remainder tax split is
/// order-sensitive, so a reordered `roundMoney` would silently shift displayed totals by cents.
@Suite("Month Data Cache Header Total Tests")
struct MonthDataCacheHeaderTotalTests {

    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Independent reference formulas (transcribed from the pre-refactor MonthPageView)

    private struct ExpectedHeader: Equatable {
        let taxableIncome: Decimal
        let untaxableIncome: Decimal
        let taxSavings: Decimal
        let summaryTax: Decimal
        let expenseTotal: Decimal
        let headerEffectiveExpenses: Decimal
        let headerRemaining: Decimal
        let headerBreakEven: Decimal
        let headerIncomeNeeded: Decimal
        let reallocationIn: Decimal
        let reallocationOut: Decimal
    }

    private func expectedHeader(incomes: [Income], expenses: [Expense], reallocations: [Reallocation],
                                 ym: YearMonth, isTaxSavingsEnabled: Bool, taxSavingsPercentage: Double) -> ExpectedHeader {
        let inc = expandedIncomes(from: incomes, month: ym.month, year: ym.year)
        let exp = expandedExpenses(from: expenses, month: ym.month, year: ym.year)
        let activeReallocs = reallocations.activeIn(yearMonth: ym)
        let positiveReallocs = reallocations.additionsIn(yearMonth: ym)
        let negativeReallocs = reallocations.deductionsIn(yearMonth: ym)

        func taxTotalForExpanded(_ expanded: [Income]) -> Decimal {
            TaxDistributionHelper.distributedTaxAmounts(
                for: expanded.map { (income: $0, amount: $0.amount) },
                defaultPercentage: taxSavingsPercentage
            ).values.sumMoney()
        }

        let taxableIncome: Decimal = isTaxSavingsEnabled ? inc.filter { $0.isTaxable }.map { $0.amount }.sumMoney() : 0
        let untaxableIncome: Decimal = isTaxSavingsEnabled
            ? inc.filter { !$0.isTaxable }.map { $0.amount }.sumMoney()
            : inc.map { $0.amount }.sumMoney()
        let isTaxActive = isTaxSavingsEnabled && taxSavingsPercentage.isEffectivelyPositive
        let taxSavings: Decimal = isTaxActive ? taxTotalForExpanded(inc) : 0
        let summaryTax: Decimal = isTaxSavingsEnabled ? taxTotalForExpanded(inc) : 0
        let expenseTotal = exp.map { $0.amount }.sumMoney()

        let reallocated = activeReallocs.map { $0.signedAmount }.sumMoney()
        var raw = roundMoney(untaxableIncome + taxableIncome)
        if isTaxActive { raw = roundMoney(raw - taxSavings) }
        raw = roundMoney(raw - expenseTotal)
        raw = roundMoney(raw + reallocated)
        let headerRemaining = raw.roundedAndNormalizedMoney()

        let positiveAmt = positiveReallocs.map { $0.amount }.sumMoney()
        let negativeAmt = negativeReallocs.map { $0.amount }.sumMoney()
        let effectiveExpenses = roundMoney(expenseTotal + negativeAmt - positiveAmt)

        let headerBreakEven: Decimal
        if isTaxActive {
            let afterTax = roundMoney(taxableIncome - taxSavings)
            let available = roundMoney(afterTax + untaxableIncome)
            headerBreakEven = max(0, roundMoney(effectiveExpenses - available))
        } else {
            headerBreakEven = max(0, roundMoney(effectiveExpenses - roundMoney(taxableIncome + untaxableIncome)))
        }

        let taxRate = (Decimal(string: String(taxSavingsPercentage)) ?? 0) / 100
        let covered = roundMoney(min(effectiveExpenses, untaxableIncome))
        let remaining = roundMoney(max(0, effectiveExpenses - covered))
        let divisor = 1 - taxRate
        let needed = divisor == 0 ? remaining : roundMoney(remaining / divisor)
        let grossNeeded = roundMoney(covered + needed)
        let headerIncomeNeeded = max(0, roundMoney(roundMoney(grossNeeded - untaxableIncome) - taxableIncome))

        let reallocIn = activeReallocs.filter { !$0.isFromEntry }.map { $0.amount }.sumMoney()
        let reallocOut = activeReallocs.filter { $0.isFromEntry }.map { $0.amount }.sumMoney()

        return ExpectedHeader(taxableIncome: taxableIncome, untaxableIncome: untaxableIncome,
                               taxSavings: taxSavings, summaryTax: summaryTax, expenseTotal: expenseTotal,
                               headerEffectiveExpenses: effectiveExpenses, headerRemaining: headerRemaining,
                               headerBreakEven: headerBreakEven, headerIncomeNeeded: headerIncomeNeeded,
                               reallocationIn: reallocIn, reallocationOut: reallocOut)
    }

    private func assertMatches(_ data: MonthExpandedData, _ expected: ExpectedHeader,
                                _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(data.taxableIncomeTotal == expected.taxableIncome, "\(label): taxableIncomeTotal", sourceLocation: sourceLocation)
        #expect(data.untaxableIncomeTotal == expected.untaxableIncome, "\(label): untaxableIncomeTotal", sourceLocation: sourceLocation)
        #expect(data.taxSavingsTotal == expected.taxSavings, "\(label): taxSavingsTotal", sourceLocation: sourceLocation)
        #expect(data.summaryTaxTotal == expected.summaryTax, "\(label): summaryTaxTotal", sourceLocation: sourceLocation)
        #expect(data.expenseTotal == expected.expenseTotal, "\(label): expenseTotal", sourceLocation: sourceLocation)
        #expect(data.headerEffectiveExpenses == expected.headerEffectiveExpenses, "\(label): headerEffectiveExpenses", sourceLocation: sourceLocation)
        #expect(data.headerRemaining == expected.headerRemaining, "\(label): headerRemaining", sourceLocation: sourceLocation)
        #expect(data.headerBreakEven == expected.headerBreakEven, "\(label): headerBreakEven", sourceLocation: sourceLocation)
        #expect(data.headerIncomeNeeded == expected.headerIncomeNeeded, "\(label): headerIncomeNeeded", sourceLocation: sourceLocation)
        #expect(data.reallocationInTotal == expected.reallocationIn, "\(label): reallocationInTotal", sourceLocation: sourceLocation)
        #expect(data.reallocationOutTotal == expected.reallocationOut, "\(label): reallocationOutTotal", sourceLocation: sourceLocation)
    }

    // MARK: - Named scenarios

    @Test("Mixed taxable/untaxable/override incomes with both-direction reallocations")
    func testMixedScenario() {
        let ym = YearMonth(year: 2026, month: 9)
        let incomes = [
            Income(name: "Salary", amount: d("1000.00"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly, isTaxable: true),
            Income(name: "Gift", amount: d("543.33"), date: date(2026, 9, 5), isRecurring: false, recurringFrequency: .monthly, isTaxable: false),
            Income(name: "Side gig", amount: d("217.77"), date: date(2026, 9, 10), isRecurring: false, recurringFrequency: .monthly, isTaxable: true, taxPercentageOverride: d("22.5"))
        ]
        let expenses = [
            Expense(name: "Rent", amount: d("812.45"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly),
            Expense(name: "Groceries", amount: d("233.19"), date: date(2026, 9, 12), isRecurring: false, recurringFrequency: .monthly)
        ]
        let reallocations = [
            Reallocation(linkedId: UUID(), amount: d("75.50"), fromMonth: 8, fromYear: 2026, toMonth: 9, toYear: 2026, isFromEntry: false),
            Reallocation(linkedId: UUID(), amount: d("40.10"), fromMonth: 9, fromYear: 2026, toMonth: 10, toYear: 2026, isFromEntry: true)
        ]
        let data = buildMonthData(incomes: incomes, expenses: expenses, reallocations: reallocations,
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: true, taxSavingsPercentage: 15.0)
        let expected = expectedHeader(incomes: incomes, expenses: expenses, reallocations: reallocations,
                                       ym: ym, isTaxSavingsEnabled: true, taxSavingsPercentage: 15.0)
        assertMatches(data, expected, "mixed scenario")
        #expect(data.summaryIncomeTotal == d("1761.10"))
    }

    @Test("Tax savings disabled: untaxable income is the full sum, not just the non-taxable subset")
    func testTaxDisabled() {
        let ym = YearMonth(year: 2026, month: 9)
        let incomes = [
            Income(name: "Salary", amount: d("1000.00"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly, isTaxable: true),
            Income(name: "Gift", amount: d("200.00"), date: date(2026, 9, 5), isRecurring: false, recurringFrequency: .monthly, isTaxable: false)
        ]
        let expenses = [Expense(name: "Rent", amount: d("500.00"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly)]
        let data = buildMonthData(incomes: incomes, expenses: expenses, reallocations: [],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: false, taxSavingsPercentage: 15.0)
        #expect(data.taxableIncomeTotal == 0)
        #expect(data.untaxableIncomeTotal == d("1200.00"))
        #expect(data.taxSavingsTotal == 0)
        #expect(data.summaryTaxTotal == 0)
        #expect(data.distributedTaxes.isEmpty)
        let expected = expectedHeader(incomes: incomes, expenses: expenses, reallocations: [],
                                       ym: ym, isTaxSavingsEnabled: false, taxSavingsPercentage: 15.0)
        assertMatches(data, expected, "tax disabled")
    }

    @Test("100% tax rate exercises the divisor == 0 guard in headerIncomeNeeded")
    func test100PercentTaxRate() {
        let ym = YearMonth(year: 2026, month: 9)
        let incomes = [
            Income(name: "Salary", amount: d("1000.00"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly, isTaxable: true),
            Income(name: "Gift", amount: d("200.00"), date: date(2026, 9, 5), isRecurring: false, recurringFrequency: .monthly, isTaxable: false)
        ]
        let expenses = [Expense(name: "Rent", amount: d("2500.00"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly)]
        let data = buildMonthData(incomes: incomes, expenses: expenses, reallocations: [],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: true, taxSavingsPercentage: 100.0)
        // Expenses ($2500) exceed all available income, so both BreakEven and IncomeNeeded are positive.
        #expect(data.headerBreakEven == d("2300.00"))
        #expect(data.headerIncomeNeeded == d("1300.00"))
        let expected = expectedHeader(incomes: incomes, expenses: expenses, reallocations: [],
                                       ym: ym, isTaxSavingsEnabled: true, taxSavingsPercentage: 100.0)
        assertMatches(data, expected, "100% tax rate")
    }

    @Test("Deficit month: expenses exceed income even without tax")
    func testDeficitMonth() {
        let ym = YearMonth(year: 2026, month: 9)
        let incomes = [Income(name: "Salary", amount: d("300.00"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly, isTaxable: true)]
        let expenses = [Expense(name: "Rent", amount: d("900.50"), date: date(2026, 9, 1), isRecurring: false, recurringFrequency: .monthly)]
        let data = buildMonthData(incomes: incomes, expenses: expenses, reallocations: [],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: false, taxSavingsPercentage: 0.0)
        #expect(data.headerRemaining == d("-600.50"))
        #expect(!data.headerRemaining.isEffectivelyPositive)
        let expected = expectedHeader(incomes: incomes, expenses: expenses, reallocations: [],
                                       ym: ym, isTaxSavingsEnabled: false, taxSavingsPercentage: 0.0)
        assertMatches(data, expected, "deficit month")
    }

    @Test("Bi-weekly recurring taxable income expands to two occurrences and taxes aggregate by UUID")
    func testRecurringMultiOccurrenceIncome() {
        let ym = YearMonth(year: 2026, month: 9)
        // Sept 1, 2026 is a Tuesday; a bi-weekly recurrence from the 1st lands on the 1st, 15th,
        // and 29th — three occurrences fit within September's 30 days.
        let incomes = [Income(name: "Biweekly Pay", amount: d("1000.00"), date: date(2026, 9, 1),
                              isRecurring: true, recurringFrequency: .biweekly, isTaxable: true)]
        let data = buildMonthData(incomes: incomes, expenses: [], reallocations: [],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: true, taxSavingsPercentage: 25.0)
        #expect(data.expandedIncomes.count == 3, "Bi-weekly from Sept 1 2026 occurs on the 1st, 15th, and 29th")
        #expect(data.taxableIncomeTotal == d("3000.00"))
        // Aggregated by UUID (all three occurrences share the source income's id): $3000 × 25% = $750,
        // not $250 (which a naive per-occurrence-then-last-wins dictionary would incorrectly give).
        #expect(data.taxSavingsTotal == d("750.00"))
        #expect(data.distributedTaxes.count == 1, "All three occurrences share one UUID key")
        let expected = expectedHeader(incomes: incomes, expenses: [], reallocations: [],
                                       ym: ym, isTaxSavingsEnabled: true, taxSavingsPercentage: 25.0)
        assertMatches(data, expected, "recurring multi-occurrence income")
    }

    @Test("Monthly payment plan expense contributes its per-month installment, not the total")
    func testPaymentPlanExpense() {
        let ym = YearMonth(year: 2026, month: 9)
        let expense = Expense(name: "New Laptop", amount: d("100.00"), date: date(2026, 7, 1),
                              endDate: date(2026, 9, 30), isRecurring: false, recurringFrequency: .monthly,
                              isMonthlyPaymentPlan: true, totalAmount: d("300.00"))
        let data = buildMonthData(incomes: [], expenses: [expense], reallocations: [],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: false, taxSavingsPercentage: 0.0)
        #expect(data.expandedExpenses.count == 1)
        #expect(data.expenseTotal == d("100.00"), "Payment plan should contribute one $100 installment for September, not the $300 total")
        let expected = expectedHeader(incomes: [], expenses: [expense], reallocations: [],
                                       ym: ym, isTaxSavingsEnabled: false, taxSavingsPercentage: 0.0)
        assertMatches(data, expected, "payment plan expense")
    }

    @Test("sortedActiveReallocations orders by createdAt then id, filtering preserves that order")
    func testSortedActiveReallocationsOrder() {
        let ym = YearMonth(year: 2026, month: 9)
        let base = Date()
        let r1 = Reallocation(linkedId: UUID(), amount: d("10.00"), fromMonth: 8, fromYear: 2026, toMonth: 9, toYear: 2026, isFromEntry: false, createdAt: base.addingTimeInterval(20))
        let r2 = Reallocation(linkedId: UUID(), amount: d("20.00"), fromMonth: 8, fromYear: 2026, toMonth: 9, toYear: 2026, isFromEntry: false, createdAt: base.addingTimeInterval(5))
        let r3 = Reallocation(linkedId: UUID(), amount: d("30.00"), fromMonth: 9, fromYear: 2026, toMonth: 10, toYear: 2026, isFromEntry: true, createdAt: base.addingTimeInterval(10))
        let data = buildMonthData(incomes: [], expenses: [], reallocations: [r1, r2, r3],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: false, taxSavingsPercentage: 0.0)
        #expect(data.sortedActiveReallocations.map(\.id) == [r2.id, r3.id, r1.id],
                "Must be sorted by createdAt ascending regardless of activeReallocations' natural order")
    }

    @Test("Empty month produces every header total as exactly zero")
    func testEmptyMonth() {
        let ym = YearMonth(year: 2026, month: 9)
        let data = buildMonthData(incomes: [], expenses: [], reallocations: [],
                                   ym: ym, weekStartDay: 1, isTaxSavingsEnabled: true, taxSavingsPercentage: 15.0)
        #expect(data.summaryIncomeTotal == 0)
        #expect(data.taxableIncomeTotal == 0)
        #expect(data.untaxableIncomeTotal == 0)
        #expect(data.expenseTotal == 0)
        #expect(data.taxSavingsTotal == 0)
        #expect(data.summaryTaxTotal == 0)
        #expect(data.headerRemaining == 0)
        #expect(data.headerBreakEven == 0)
        #expect(data.headerIncomeNeeded == 0)
        #expect(data.distributedTaxes.isEmpty)
        #expect(data.sortedActiveReallocations.isEmpty)
    }

    // MARK: - Calendar grid structural checks (moved from BudgetPageView unchanged; verify the move didn't break it)

    @Test("computeCalendarWeeks produces the correct day count and leading padding for known months")
    func testCalendarWeeksStructure() {
        // September 2026 has 30 days and starts on a Tuesday (weekday 3).
        let weeksSundayStart = computeCalendarWeeks(year: 2026, month: 9, weekStartDay: 1)
        let flatDays = weeksSundayStart.flatMap { $0 }
        let actualDays = flatDays.compactMap { $0 }
        #expect(actualDays.count == 30, "September has 30 days")
        #expect(actualDays == Array(1...30))
        #expect(flatDays.prefix(2) == [nil, nil], "Sunday-start week should have 2 leading padding cells before Tuesday the 1st")

        // Monday-start (weekStartDay 2) shifts the leading padding by one day.
        let weeksMondayStart = computeCalendarWeeks(year: 2026, month: 9, weekStartDay: 2)
        #expect(weeksMondayStart.flatMap { $0 }.prefix(1) == [nil], "Monday-start week should have 1 leading padding cell before Tuesday the 1st")

        // February 2026 (non-leap) has 28 days.
        let febWeeks = computeCalendarWeeks(year: 2026, month: 2, weekStartDay: 1)
        #expect(febWeeks.flatMap { $0 }.compactMap { $0 }.count == 28)
    }

    // MARK: - Randomized fuzz test

    /// Deterministic seeded PRNG (xorshift64) — reproducible across runs so a failure always
    /// points at the same fixed scenario instead of a flaky, unreproducible one.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0xdeadbeef : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    @Test("Fuzz: buildMonthData header totals match independently-recomputed formulas across 300 randomized scenarios")
    func testFuzzHeaderTotals() {
        var rng = SeededGenerator(seed: 0x42)
        let ym = YearMonth(year: 2026, month: 9)

        for trial in 0..<300 {
            var incomes: [Income] = []
            for i in 0..<Int.random(in: 0...6, using: &rng) {
                let amount = Decimal(Int.random(in: 0...500_000, using: &rng)) / 100
                let taxable = Bool.random(using: &rng)
                let hasOverride = Int.random(in: 0...9, using: &rng) < 3
                let override: Decimal? = hasOverride ? Decimal(Int.random(in: 0...10_000, using: &rng)) / 100 : nil
                let isRecurring = Int.random(in: 0...9, using: &rng) < 2
                let day = Int.random(in: 1...28, using: &rng)
                incomes.append(Income(name: "Inc\(trial)-\(i)", amount: amount, date: date(2026, 9, day),
                                       isRecurring: isRecurring, recurringFrequency: .biweekly,
                                       isTaxable: taxable, taxPercentageOverride: override))
            }
            var expenses: [Expense] = []
            for i in 0..<Int.random(in: 0...6, using: &rng) {
                let amount = Decimal(Int.random(in: 0...500_000, using: &rng)) / 100
                let day = Int.random(in: 1...28, using: &rng)
                let isPaymentPlan = Int.random(in: 0...9, using: &rng) < 2
                if isPaymentPlan {
                    let total = amount * 3
                    expenses.append(Expense(name: "Exp\(trial)-\(i)", amount: amount, date: date(2026, 8, day),
                                            endDate: date(2026, 9, 28), isRecurring: false, recurringFrequency: .monthly,
                                            isMonthlyPaymentPlan: true, totalAmount: total))
                } else {
                    expenses.append(Expense(name: "Exp\(trial)-\(i)", amount: amount, date: date(2026, 9, day),
                                            isRecurring: false, recurringFrequency: .monthly))
                }
            }
            var reallocations: [Reallocation] = []
            for _ in 0..<Int.random(in: 0...3, using: &rng) {
                let amount = Decimal(Int.random(in: 0...100_000, using: &rng)) / 100
                let isFrom = Bool.random(using: &rng)
                reallocations.append(Reallocation(linkedId: UUID(), amount: amount,
                                                   fromMonth: isFrom ? 9 : 8, fromYear: 2026,
                                                   toMonth: isFrom ? 10 : 9, toYear: 2026,
                                                   isFromEntry: isFrom))
            }
            let isTaxSavingsEnabled = Bool.random(using: &rng)
            let taxSavingsPercentage = Double(Int.random(in: 0...10_000, using: &rng)) / 100.0

            let data = buildMonthData(incomes: incomes, expenses: expenses, reallocations: reallocations,
                                       ym: ym, weekStartDay: 1,
                                       isTaxSavingsEnabled: isTaxSavingsEnabled, taxSavingsPercentage: taxSavingsPercentage)
            let expected = expectedHeader(incomes: incomes, expenses: expenses, reallocations: reallocations,
                                           ym: ym, isTaxSavingsEnabled: isTaxSavingsEnabled, taxSavingsPercentage: taxSavingsPercentage)
            assertMatches(data, expected, "trial \(trial) (tax=\(isTaxSavingsEnabled)@\(taxSavingsPercentage)%, \(incomes.count) incomes, \(expenses.count) expenses, \(reallocations.count) reallocs)")

            // Structural invariants independent of the reference-formula replication.
            let expandedIncomeSum = data.expandedIncomes.map { $0.amount }.sumMoney()
            #expect(data.summaryIncomeTotal == expandedIncomeSum, "trial \(trial): summaryIncomeTotal")
            if isTaxSavingsEnabled {
                #expect(data.taxableIncomeTotal + data.untaxableIncomeTotal == data.summaryIncomeTotal,
                        "trial \(trial): taxable + untaxable must equal summary income when tax savings enabled")
                #expect(data.distributedTaxes.values.sumMoney() == data.summaryTaxTotal,
                        "trial \(trial): distributedTaxes must sum to summaryTaxTotal")
            } else {
                #expect(data.distributedTaxes.isEmpty, "trial \(trial): distributedTaxes must be empty when tax savings disabled")
            }
            #expect(!data.headerBreakEven.isEffectivelyNegative, "trial \(trial): headerBreakEven is a max(0, …) clamp")
            #expect(!data.headerIncomeNeeded.isEffectivelyNegative, "trial \(trial): headerIncomeNeeded is a max(0, …) clamp")
        }
    }
}

// MARK: - Backup and Duplication Data-Completeness Tests
/// Guards the fields added to close gaps in backup/restore and whole-budget duplication:
/// `BackupItem`/`BackupAppSettings` decoding safely when older backup JSON is missing newly
/// added keys, `hasDataChanged` noticing a `calendarWeekStartDay` change, and the
/// `duplicateForBudgetCopy` helpers preserving trash state, reallocation attachments, and
/// reimbursement links that the plain `duplicate()` methods intentionally drop.
@Suite("Backup and Duplication Data-Completeness Tests")
struct BackupAndDuplicationDataCompletenessTests {

    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - BackupItem / BackupAppSettings back-compat decoding

    @Test("BackupItem decodes JSON missing calendarWeekStartDay (older backup) as nil")
    func testBackupItemBackCompatMissingCalendarWeekStartDay() throws {
        let json = """
        {
            "timestamp": "2026-01-01T00:00:00Z",
            "lastOpenedDate": "2026-01-01T00:00:00Z",
            "lastModifiedDate": "2026-01-01T00:00:00Z",
            "name": "Old Budget",
            "manualSortOrder": 0,
            "taxSavingsPercentage": 11.0,
            "isTaxSavingsEnabled": true,
            "itemType": "Budget"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(BackupItem.self, from: json.data(using: .utf8)!)
        #expect(item.calendarWeekStartDay == nil)
    }

    @Test("BackupAppSettings decodes JSON missing the new keys (older backup) as nil")
    func testBackupAppSettingsBackCompatMissingNewKeys() throws {
        let json = """
        {
            "selectedCurrency": "USD ($)",
            "highlightColorHex": "FF7EB5"
        }
        """
        let settings = try JSONDecoder().decode(BackupAppSettings.self, from: json.data(using: .utf8)!)
        #expect(settings.highlightColorComponents == nil)
        #expect(settings.vehicles == nil)
        #expect(settings.appContextMenuBudgetTimestamp == nil)
    }

    // MARK: - BackupItem change detection

    private func makeBackupItem(calendarWeekStartDay: Int?) -> BackupItem {
        BackupItem(
            timestamp: date(2026, 1, 1), lastOpenedDate: date(2026, 1, 1), lastModifiedDate: date(2026, 1, 1),
            name: "Test", budgetAmount: nil, manualSortOrder: 0, taxSavingsPercentage: 11.0,
            isTaxSavingsEnabled: true, itemType: "Budget", targetYear: nil, deletedDate: nil,
            expensesData: nil, incomesData: nil, attachmentsData: nil, reallocationsData: nil,
            odometerReadingsData: nil, taxesData: nil, isAutoIncomeDisabled: nil,
            disabledAutoIncomeAmount: nil, disabledAutoIncomeFrequency: nil, disabledAutoIncomeDate: nil,
            lastTaxSavingsPercentage: nil, hideExpensesRow: nil, hideTaxesGoalRow: nil,
            hideReallocationsRow: nil, hideIncomeSurplusRow: nil, hideOtherIncomeRow: nil,
            hiddenFilterCategories: nil, calendarWeekStartDay: calendarWeekStartDay
        )
    }

    @Test("BackupItem equality distinguishes items differing only in calendarWeekStartDay")
    func testBackupItemEqualityCoversCalendarWeekStartDay() {
        let base = makeBackupItem(calendarWeekStartDay: nil)
        let changed = makeBackupItem(calendarWeekStartDay: 2)
        #expect(base != changed, "hasDataChanged must notice a week-start change, or automatic backups get skipped")
    }

    // MARK: - duplicateForBudgetCopy fidelity

    @Test("Expense.duplicateForBudgetCopy preserves deletedDate and remaps reimbursedByIncomeId")
    func testExpenseDuplicateForBudgetCopy() {
        let oldIncomeId = UUID()
        let newIncomeId = UUID()
        let trashedDate = date(2026, 3, 1)
        let attachment = Attachment(data: Data([1, 2, 3]), fileName: "receipt.png", fileType: .image)
        let original = Expense(name: "Groceries", amount: d("42.00"), date: date(2026, 3, 1),
                                isRecurring: false, recurringFrequency: .monthly,
                                attachments: [attachment], reimbursedByIncomeId: oldIncomeId,
                                deletedDate: trashedDate)

        let copy = original.duplicateForBudgetCopy(incomeIDMap: [oldIncomeId: newIncomeId])

        #expect(copy.id != original.id, "Budget-copy must mint a fresh top-level ID")
        #expect(copy.attachments.first?.id != attachment.id, "Budget-copy must mint fresh attachment IDs")
        #expect(copy.attachments.first?.data == attachment.data)
        #expect(copy.name == original.name)
        #expect(copy.amount == original.amount)
        #expect(copy.deletedDate == trashedDate, "Trashed expenses must stay trashed in a whole-budget copy")
        #expect(copy.reimbursedByIncomeId == newIncomeId, "Reimbursement link must point at the copied income's new ID")
    }

    @Test("Expense.duplicateForBudgetCopy clears reimbursedByIncomeId when the linked income wasn't carried over")
    func testExpenseDuplicateForBudgetCopyDropsUnmatchedReimbursement() {
        let orphanedIncomeId = UUID()
        let original = Expense(name: "Rent", amount: d("10.00"), date: date(2026, 3, 1),
                                isRecurring: false, recurringFrequency: .monthly,
                                reimbursedByIncomeId: orphanedIncomeId)

        let copy = original.duplicateForBudgetCopy(incomeIDMap: [:])

        #expect(copy.reimbursedByIncomeId == nil, "A reimbursement link to an income absent from the map must be dropped, not left dangling")
    }

    @Test("Income.duplicateForBudgetCopy preserves deletedDate and mints a fresh ID")
    func testIncomeDuplicateForBudgetCopy() {
        let trashedDate = date(2026, 3, 2)
        let original = Income(name: "Paycheck", amount: d("500.00"), date: date(2026, 3, 1),
                               isRecurring: false, recurringFrequency: .monthly, deletedDate: trashedDate)

        let copy = original.duplicateForBudgetCopy()

        #expect(copy.id != original.id)
        #expect(copy.amount == original.amount)
        #expect(copy.deletedDate == trashedDate, "Trashed incomes must stay trashed in a whole-budget copy")
    }

    @Test("BudgetAttachment.duplicateForBudgetCopy preserves deletedDate and mints a fresh ID")
    func testBudgetAttachmentDuplicateForBudgetCopy() {
        let trashedDate = date(2026, 3, 3)
        let original = BudgetAttachment(data: Data([9, 9]), fileName: "invoice.pdf", fileType: .pdf,
                                         month: 3, year: 2026, deletedDate: trashedDate)

        let copy = original.duplicateForBudgetCopy()

        #expect(copy.id != original.id)
        #expect(copy.data == original.data)
        #expect(copy.month == original.month && copy.year == original.year)
        #expect(copy.deletedDate == trashedDate, "Trashed attachments must stay trashed in a whole-budget copy")
    }

    @Test("Reallocation.duplicateForBudgetCopy preserves attachments and consistently remaps id/linkedId across a from/to pair")
    func testReallocationDuplicateForBudgetCopyPreservesAttachmentsAndLinks() {
        let attachment = Attachment(data: Data([7]), fileName: "note.txt", fileType: .document)
        let fromEntry = Reallocation(linkedId: UUID(), amount: d("50.00"),
                                      fromMonth: 3, fromYear: 2026, toMonth: 4, toYear: 2026,
                                      isFromEntry: true, attachments: [attachment])
        // The paired "to" entry mirrors how BudgetPageView links a reallocation pair: its own id
        // is the from-entry's linkedId, and its linkedId points back at the from-entry's id.
        let toEntry = Reallocation(id: fromEntry.linkedId, linkedId: fromEntry.id, amount: d("50.00"),
                                    fromMonth: 3, fromYear: 2026, toMonth: 4, toYear: 2026, isFromEntry: false)

        var idMap: [UUID: UUID] = [:]
        let fromCopy = fromEntry.duplicateForBudgetCopy(idMap: &idMap)
        let toCopy = toEntry.duplicateForBudgetCopy(idMap: &idMap)

        #expect(fromCopy.attachments.first?.data == attachment.data, "Reallocation attachments must survive a whole-budget copy")
        #expect(fromCopy.attachments.first?.id != attachment.id)
        #expect(fromCopy.id != fromEntry.id && toCopy.id != toEntry.id, "Both halves of the pair must get fresh top-level IDs")
        #expect(fromCopy.linkedId == toCopy.id, "The copied pair must still link to each other, not the originals")
        #expect(toCopy.linkedId == fromCopy.id, "The copied pair must still link to each other, not the originals")
    }

    @Test("OdometerReading.duplicateForBudgetCopy mints a fresh ID and fresh attachment IDs")
    func testOdometerReadingDuplicateForBudgetCopy() {
        let attachment = Attachment(data: Data([4]), fileName: "odo.jpg", fileType: .image)
        let original = OdometerReading(vehicle: "Truck", odometerValue: 12345, date: date(2026, 3, 1),
                                        attachments: [attachment])

        let copy = original.duplicateForBudgetCopy()

        #expect(copy.id != original.id)
        #expect(copy.attachments.first?.id != attachment.id)
        #expect(copy.vehicle == original.vehicle && copy.odometerValue == original.odometerValue)
    }
}
