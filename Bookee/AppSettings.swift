//
//  AppSettings.swift
//  Bookee
//
//  Created by Kara Eveland on 3/4/26.
//

import Foundation
import SwiftUI

// MARK: - App Settings Enums

/// Defines the app's appearance mode preference (light, dark, or system default).
enum AppearanceMode: String, CaseIterable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    /// Returns the SwiftUI ColorScheme, or nil for system (allowing automatic appearance).
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// Defines date formatting options with example displays as raw values.
enum DateFormat: String, CaseIterable, Codable {
    case short = "02/15/26"
    case numericPadded = "02/15/2026"
    case abbreviated = "Feb 15, 2026"
    case long = "February 15, 2026"

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

/// Defines sorting options for books in the library.
enum SortOrder: String, CaseIterable, Codable {
    case alphabetical = "Title"
    case genreAlphabetical = "Genre"
    case seriesAlphabetical = "Series"
    case statusAlphabetical = "Status"
    case rating = "Rating"
    case authorAlphabetical = "Author"
    case manual = "Manual"
}

// MARK: - Genre / Category Helpers

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
enum SettingsKey {
    static let highlightColorHex = "highlightColorHex"
    static let showFooters = "showFooters"
    static let dateFormat = "dateFormat"
    static let sortOrder = "sortOrder"
    static let appearanceMode = "appearanceMode"
    static let userName = "userName"
    static let genres = "genres"
}

// MARK: - Settings Defaults

enum SettingsDefault {
    /// Pink — matches the app-level .tint set in BookeeApp.swift.
    static let highlightColorHex = "FF7EB5"
    static let showFooters = true
    /// Sentinel value used to represent "no genre assigned" in filter logic.
    static let uncategorizedSentinel = "__Uncategorized__"
}

// MARK: - Highlight Color Storage

/// A DynamicProperty that reads the user-selected accent colour from AppStorage.
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
