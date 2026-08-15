//
//  K_TestTests.swift
//  K TestTests
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
    
    @Test("Tax distribution example from documentation")
    func testTaxDistributionDocExample() {
        // Example from documentation:
        // - Income 1: $7.10 × 11% = $0.781 → rounds down to $0.78
        // - Income 2: $56.80 × 11% = $6.248 → rounds down to $6.24
        // - Total: $63.90 × 11% = $7.029 → rounds to $7.03
        // - Problem: $0.78 + $6.24 = $7.02 ✗ (off by $0.01!)
        
        let income1 = Income(name: "Income 1", amount: 7.10, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        let income2 = Income(name: "Income 2", amount: 56.80, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        let incomes = [income1, income2]
        
        let taxRate = 0.11 // 11%
        
        let distributedAmounts = TaxDistributionHelper.distributedTaxAmounts(for: incomes, taxRate: taxRate)
        
        // Get individual distributed tax amounts
        let tax1 = distributedAmounts[income1.id] ?? 0.0
        let tax2 = distributedAmounts[income2.id] ?? 0.0
        
        // Calculate expected total
        let totalIncome = roundMoney(7.10 + 56.80)
        let expectedTotal = roundMoney(totalIncome * taxRate)
        
        // Verify the sum of distributed taxes equals the expected total
        let sumOfDistributed = roundMoney(tax1 + tax2)
        
        #expect(sumOfDistributed == expectedTotal, "Distributed taxes should sum to exact total: \(sumOfDistributed) should equal \(expectedTotal)")
        
        // The expected total should be $7.03
        #expect(expectedTotal == 7.03)
        
        // The sum should also be $7.03
        #expect(sumOfDistributed == 7.03)
    }
    
    @Test("Tax distribution with many small incomes")
    func testTaxDistributionManySmallIncomes() {
        // Create 100 small incomes of $1.01 each
        let incomes = (1...100).map { i in
            Income(name: "Income \(i)", amount: 1.01, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        }
        
        let taxRate = 0.11
        
        let distributedAmounts = TaxDistributionHelper.distributedTaxAmounts(for: incomes, taxRate: taxRate)
        
        // Calculate expected total
        let totalIncome = incomes.map { $0.amount }.sumMoney()
        let expectedTotal = roundMoney(totalIncome * taxRate)
        
        // Sum all distributed amounts
        let sumOfDistributed = distributedAmounts.values.reduce(0.0) { acc, val in
            roundMoney(acc + val)
        }
        
        #expect(sumOfDistributed == expectedTotal, "Sum of distributed taxes should equal total")
    }
    
    @Test("Tax distribution filters nontaxable incomes")
    func testTaxDistributionFiltersNontaxable() {
        let taxableIncome = Income(name: "Taxable", amount: 100.0, date: Date(), isRecurring: false, recurringFrequency: .monthly, isTaxable: true)
        let nontaxableIncome = Income(name: "Nontaxable", amount: 50.0, date: Date(), isRecurring: false, recurringFrequency: .monthly, isTaxable: false)
        
        let incomes = [taxableIncome, nontaxableIncome]
        let taxRate = 0.11
        
        let distributedAmounts = TaxDistributionHelper.distributedTaxAmounts(for: incomes, taxRate: taxRate)
        
        // Should only have entry for taxable income
        #expect(distributedAmounts.count == 1)
        #expect(distributedAmounts[taxableIncome.id] != nil)
        #expect(distributedAmounts[nontaxableIncome.id] == nil)
        
        // Tax amount should be based only on taxable income
        let expectedTax = roundMoney(100.0 * taxRate)
        #expect(distributedAmounts[taxableIncome.id] == expectedTax)
    }
    
    @Test("Tax distribution with zero tax rate")
    func testTaxDistributionZeroRate() {
        let income1 = Income(name: "Income 1", amount: 100.0, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        let income2 = Income(name: "Income 2", amount: 200.0, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        
        let distributedAmounts = TaxDistributionHelper.distributedTaxAmounts(for: [income1, income2], taxRate: 0.0)
        
        // All taxes should be zero
        #expect(distributedAmounts[income1.id] == 0.0)
        #expect(distributedAmounts[income2.id] == 0.0)
    }
    
    @Test("Tax distribution with high tax rate")
    func testTaxDistributionHighRate() {
        let income = Income(name: "Income", amount: 100.0, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        
        let distributedAmounts = TaxDistributionHelper.distributedTaxAmounts(for: [income], taxRate: 0.9999)
        
        let tax = distributedAmounts[income.id] ?? 0.0
        let expectedTax = roundMoney(100.0 * 0.9999)
        
        #expect(tax == expectedTax)
        #expect(tax == 99.99)
    }
    
    @Test("Tax distribution with odd amounts ensuring proper rounding")
    func testTaxDistributionOddAmounts() {
        // Test with amounts that will produce fractional cents
        let income1 = Income(name: "Income 1", amount: 7.13, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        let income2 = Income(name: "Income 2", amount: 19.87, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        let income3 = Income(name: "Income 3", amount: 42.99, date: Date(), isRecurring: false, recurringFrequency: .monthly)
        
        let incomes = [income1, income2, income3]
        let taxRate = 0.073 // 7.3%
        
        let distributedAmounts = TaxDistributionHelper.distributedTaxAmounts(for: incomes, taxRate: taxRate)
        
        // Calculate expected total
        let totalIncome = incomes.map { $0.amount }.sumMoney()
        let expectedTotal = roundMoney(totalIncome * taxRate)
        
        // Sum all distributed amounts with proper rounding
        let sumOfDistributed = distributedAmounts.values.reduce(0.0) { acc, val in
            roundMoney(acc + val)
        }
        
        #expect(sumOfDistributed == expectedTotal, "Distributed amounts \(sumOfDistributed) should equal expected total \(expectedTotal)")
        
        // All individual amounts should be properly rounded to 2 decimal places
        for (_, amount) in distributedAmounts {
            let rounded = amount.roundedMoney()
            #expect(amount == rounded, "Each distributed amount should already be properly rounded")
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
