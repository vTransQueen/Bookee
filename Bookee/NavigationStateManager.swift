//
//  NavigationStateManager.swift
//  Bookee
//
//  Created by Kara Eveland on 3/14/26.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Navigation State Manager

/// Manages persistence and restoration of navigation state across app launches.
@Observable
class NavigationStateManager {
    static let shared = NavigationStateManager()

    var navigationPath = NavigationPath()

    static let navigationStateKey = "savedNavigationState"

    private init() {}

    // MARK: - State Persistence

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

    func saveIsViewingSettings(_ isViewing: Bool) {
        updateState { $0.isViewingSettings = isViewing }
    }
}

// MARK: - Navigation State Model

struct NavigationState: Codable {
    var isViewingSettings: Bool = false
}
