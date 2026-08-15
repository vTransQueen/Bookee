//
//  AppSettings.swift
//  K Test
//
//  Created by Kara Eveland on 3/4/26.
//

import Foundation
import SwiftUI

// MARK: - App Settings Enums
/// Defines enums for user preferences including currency, appearance, date formatting, and sort order.
/// These enums conform to CaseIterable and Codable for easy persistence and enumeration.

/// Represents supported currencies with their display names including symbols.
/// Provides computed properties to extract currency codes and symbols separately.
enum Currency: String, CaseIterable, Codable {
    case usd = "USD ($)"
    case eur = "EUR (€)"
    case gbp = "GBP (£)"
    case jpy = "JPY (¥)"
    case cad = "CAD ($)"
    case aud = "AUD ($)"
    case chf = "CHF (CHF)"
    case cny = "CNY (¥)"
    case inr = "INR (₹)"
    case mxn = "MXN ($)"
    case brl = "BRL (R$)"
    case krw = "KRW (₩)"
    
    /// Returns the three-letter currency code (e.g., "USD", "EUR")
    var code: String {
        String(rawValue.prefix(3))
    }
    
    /// Returns the currency symbol for formatting amounts (e.g., "$", "€", "¥")
    var symbol: String {
        switch self {
        case .usd, .cad, .aud, .mxn: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy, .cny: return "¥"
        case .chf: return "CHF"
        case .inr: return "₹"
        case .brl: return "R$"
        case .krw: return "₩"
        }
    }
}

/// Defines the app's appearance mode preference (light, dark, or system default).
/// Provides a conversion to SwiftUI ColorScheme for view-level appearance control.
enum AppearanceMode: String, CaseIterable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
    
    /// Returns the SwiftUI ColorScheme, or nil for system (allowing automatic appearance)
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// Defines date formatting options with example displays as raw values.
/// Provides Date.FormatStyle instances for both date-only and date-with-time formatting.
enum DateFormat: String, CaseIterable, Codable {
    case short = "02/15/26"
    case numericPadded = "02/15/2026"
    case abbreviated = "Feb 15, 2026"
    case long = "February 15, 2026"
    
    /// Returns the Date.FormatStyle for displaying dates without time
    var style: Date.FormatStyle {
        switch self {
        case .long:
            return .init(date: .long, time: .omitted)
        case .abbreviated:
            return .init(date: .abbreviated, time: .omitted)
        case .numericPadded:
            return .init().month(.twoDigits).day(.twoDigits).year(.defaultDigits)
        case .short:
            return .init().month(.twoDigits).day(.twoDigits).year(.twoDigits)
        }
    }
    
    /// Returns the Date.FormatStyle for displaying dates with time
    var styleWithTime: Date.FormatStyle {
        switch self {
        case .long:
            return .init(date: .long, time: .shortened)
        case .abbreviated:
            return .init(date: .abbreviated, time: .shortened)
        case .numericPadded:
            return .init().month(.twoDigits).day(.twoDigits).year(.defaultDigits).hour().minute()
        case .short:
            return .init().month(.twoDigits).day(.twoDigits).year(.twoDigits).hour().minute()
        }
    }
}

/// Defines sorting options for items in the app
enum SortOrder: String, CaseIterable, Codable {
    case manual = "Manual"
    case dateAdded = "Date Added"
    case dateOpened = "Date Opened"
}

// MARK: - Transaction Category Helpers

extension String {
    var asCategories: [String] {
        guard let data = data(using: .utf8),
              let categories = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return categories
    }
}

extension Array where Element == String {
    var asAppStorageString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}

// MARK: - Settings Keys

/// Canonical string keys for all @AppStorage values.
/// Use these constants instead of raw strings to catch typos at compile time.
enum SettingsKey {
    static let highlightColorHex = "highlightColorHex"
    static let showFooters = "showFooters"
    static let selectedCurrency = "selectedCurrency"
    static let dateFormat = "dateFormat"
    static let sortOrder = "sortOrder"
    static let appearanceMode = "appearanceMode"
    static let userName = "userName"
    static let transactionCategories = "transactionCategories"
}

// MARK: - Settings Defaults

/// Canonical default values matching the @AppStorage declarations throughout the app.
/// Centralising these prevents drift (e.g. one view defaulting to blue while the app uses pink).
enum SettingsDefault {
    /// Pink — matches the app-level .tint set in BookeeApp.swift.
    static let highlightColorHex = "FF7EB5"
    static let showFooters = true
    /// Sentinel value used to represent "no category assigned" in filter and category logic.
    static let uncategorizedSentinel = "__Uncategorized__"
}

// MARK: - Highlight Color Storage

/// A DynamicProperty that reads the user-selected accent colour from AppStorage.
/// Replaces the two-line @AppStorage + computed-property pattern used in 9+ views.
///
/// Usage: `@HighlightColorStorage private var highlightColor`
/// - `highlightColor` (wrappedValue) gives the current `Color`
/// - `$highlightColor` (projectedValue) gives a `Binding<String>` to the raw hex string
@propertyWrapper
struct HighlightColorStorage: DynamicProperty {
    @AppStorage(SettingsKey.highlightColorHex)
    private var hex: String = SettingsDefault.highlightColorHex

    var wrappedValue: Color { Color(hex: hex) }

    /// Binding to the raw hex string — used by SettingsView to save colour picker changes.
    var projectedValue: Binding<String> { $hex }
}
