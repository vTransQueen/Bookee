//
//  NavigationStateManager.swift
//  K Test
//
//  Created by Kara Eveland on 3/14/26.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Navigation State Manager

/// Manages the persistence and restoration of navigation state across app launches.
/// Uses UserDefaults to store navigation state and item timestamps as unique identifiers.
@Observable
class NavigationStateManager {
    /// Shared singleton instance
    static let shared = NavigationStateManager()
    
    /// The current navigation path (not persisted to UserDefaults)
    var navigationPath = NavigationPath()
    
    /// Pending item timestamp to be resolved when ModelContext becomes available
    var pendingItemTimestamp: Date?
    
    /// Pending year-month to be pushed after item restoration
    var pendingYearMonth: YearMonth?

    /// The year-month last actively viewed in MonthDetailsPageView (not persisted).
    /// Updated by MonthDetailsPageView as the user navigates months; read and cleared
    /// by BudgetVisualizerPageView on reappear to scroll to the correct month.
    var viewedYearMonth: YearMonth?

    /// Flag indicating whether Settings view should be restored on first appear
    var shouldRestoreSettings: Bool = false
    
    /// UserDefaults key for storing the serialized navigation state
    static let navigationStateKey = "savedNavigationState"

    private init() {
        // During initialization, check if Settings view was active when the app was last backgrounded.
        // If so, set a flag to restore Settings view when the app UI appears.
        if let data = UserDefaults.standard.data(forKey: Self.navigationStateKey),
           let state = try? JSONDecoder().decode(NavigationState.self, from: data),
           state.isViewingSettings {
            shouldRestoreSettings = true
            print("📂 Settings restoration flagged during initialization")
        }
    }

    // MARK: - State Persistence

    /// Loads the stored state, applies `update`, then re-saves it atomically.
    private func updateState(_ update: (inout NavigationState) -> Void) {
        var state = NavigationState()
        if let data = UserDefaults.standard.data(forKey: Self.navigationStateKey),
           let decoded = try? JSONDecoder().decode(NavigationState.self, from: data) {
            state = decoded
        }
        update(&state)
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: Self.navigationStateKey)
        }
    }

    /// Legacy method that logs navigation state persistence.
    func saveNavigationState(modelContext: ModelContext) {
        print("💾 Navigation state persisted to UserDefaults")
    }

    func saveCurrentItem(_ item: Item?) {
        updateState { $0.currentItemTimestamp = item?.timestamp }
        print("💾 Current item saved: \(item?.name ?? "nil")")
    }

    func saveIsViewingSettings(_ isViewing: Bool) {
        updateState { $0.isViewingSettings = isViewing }
        print("💾 Settings view state saved: \(isViewing)")
    }

    func savePresentedSheet(_ sheet: PresentedSheet?) {
        updateState { $0.presentedSheet = sheet }
        print("💾 Presented sheet saved: \(sheet?.rawValue ?? "nil")")
    }

    func saveEditingItem(_ item: Item?) {
        updateState { $0.editingItemTimestamp = item?.timestamp }
        print("💾 Editing item saved: \(item?.name ?? "nil")")
    }

    func saveCurrentYearMonth(_ yearMonth: YearMonth?) {
        updateState { $0.currentYearMonth = yearMonth }
        print("💾 Current year-month saved: \(yearMonth.map { "\($0.month)/\($0.year)" } ?? "nil")")
    }
    
    // MARK: - State Restoration
    
    /// Loads and decodes the saved navigation state from UserDefaults.
    /// - Parameter modelContext: The SwiftData model context (unused in current implementation)
    /// - Returns: The decoded NavigationState if found and valid, nil otherwise
    func restoreNavigationState(modelContext: ModelContext) -> NavigationState? {
        guard let data = UserDefaults.standard.data(forKey: Self.navigationStateKey),
              let state = try? JSONDecoder().decode(NavigationState.self, from: data) else {
            print("📂 No saved navigation state found")
            return nil
        }
        
        print("📂 Navigation state restored")
        return state
    }
    
    /// Looks up an Item object by its timestamp using SwiftData.
    /// Fetches all items and searches for one with a matching timestamp.
    /// - Parameters:
    ///   - timestamp: The unique timestamp identifier of the item
    ///   - modelContext: The SwiftData model context used to fetch items
    /// - Returns: The matching Item if found, nil if the item doesn't exist or fetch fails
    func resolveItem(from timestamp: Date, modelContext: ModelContext) -> Item? {
        // Fetch all items from SwiftData
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? modelContext.fetch(descriptor) else {
            print("❌ Could not fetch items")
            return nil
        }
        
        // Find the item with matching timestamp
        let item = allItems.first { item in
            item.timestamp == timestamp
        }
        
        if item == nil {
            print("❌ Could not find item with timestamp: \(timestamp)")
        } else {
            print("✅ Resolved item: \(item?.name ?? "Unnamed")")
        }
        
        return item
    }
    
    /// Removes all saved navigation state from UserDefaults.
    func clearNavigationState() {
        UserDefaults.standard.removeObject(forKey: Self.navigationStateKey)
        print("🗑️ Navigation state cleared")
    }
}

// MARK: - Navigation State Model

/// Codable structure representing the complete navigation state of the app.
/// Persisted to UserDefaults and restored on app launch.
struct NavigationState: Codable {
    /// The timestamp of the currently viewed item (serves as a unique identifier for restoration)
    var currentItemTimestamp: Date?
    
    /// Whether the Settings view is currently being displayed
    var isViewingSettings: Bool = false
    
    /// The currently presented sheet, if any
    var presentedSheet: PresentedSheet?
    
    /// The timestamp of the item currently being edited in a sheet
    var editingItemTimestamp: Date?
    
    /// The currently viewed year-month in the month details page, if any
    var currentYearMonth: YearMonth?
}

// MARK: - Presented Sheet Enum

/// Defines the types of sheets that can be presented in the app.
/// Conforms to Codable for persistence in NavigationState.
enum PresentedSheet: String, Codable {
    case itemDetail
    // Add more sheet types here as needed
}
