//
//  PercentageFormatter.swift
//  Bookee
//
//  Created by Kara Eveland on 2/17/26.
//

import Foundation

/// Provides formatting utilities for percentage values with percent sign and decimal handling
struct PercentageFormatter {
    /// Formats a string input as percentage, validating input and enforcing maximum value constraint
    /// - Parameters:
    ///   - oldValue: The previous formatted string (returned if new input is invalid)
    ///   - newValue: The raw user input string to validate and format
    ///   - percentage: Inout parameter that stores the numeric value without formatting (capped at maxValue)
    ///   - maxValue: The maximum allowed percentage value (defaults to 100)
    /// - Returns: The formatted percentage string (e.g., "12.5%") or empty string if no input
    static func format(oldValue: String, newValue: String, percentage: inout Double, maxValue: Double = 100) -> String {
        // Strip percent sign to get raw numeric input
        let cleanedNew = newValue.replacingOccurrences(of: "%", with: "")
        
        // Allow only digits and decimal point
        let filtered = cleanedNew.filter { "0123456789.".contains($0) }
        
        // Reject input with multiple decimal points
        let components = filtered.components(separatedBy: ".")
        if components.count > 2 {
            return oldValue
        }
        
        // Reject more than 2 decimal places (e.g., "12.345" is invalid)
        if components.count == 2 && components[1].count > 2 {
            return oldValue
        }
        
        // Parse and round numeric value to prevent floating point precision issues
        let value = (Double(filtered) ?? 0.0).roundedMoney()
        
        // Enforce maximum value constraint and format with 1 decimal place
        if value > maxValue {
            percentage = maxValue.roundedMoney()
            return String(format: "%.1f%%", maxValue)
        }
        
        // Store the numeric value with proper rounding to prevent floating point precision issues
        percentage = value
        
        // Apply percent sign formatting
        if !filtered.isEmpty {
            return filtered + "%"
        } else {
            return ""
        }
    }
    
    /// Formats a percentage value for a text field without a percent sign, preserving up to
    /// 2 significant decimal places and stripping trailing zeros. Uses integer-cent arithmetic
    /// to avoid floating-point ambiguity on the decimal-place boundary (e.g. 11.1 × 10 is not
    /// exactly 111.0 in IEEE 754, so the modulo test must run on Int cents).
    ///
    /// This prevents the "%.1f" truncation that silently rounds 11.55 → "11.6" in the text
    /// field, which would corrupt the stored rate the next time focus is lost.
    ///
    /// Examples: 11.55 → "11.55", 11.50 → "11.5", 11.00 → "11", 100.0 → "100"
    static func formatForTextField(_ value: Double) -> String {
        let v = value.roundedMoney()
        let cents = Int((v * 100).rounded())
        if cents % 100 == 0 { return String(cents / 100) }
        if cents % 10 == 0 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}


