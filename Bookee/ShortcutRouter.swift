//
//  ShortcutRouter.swift
//  Bookee
//
//  Navigates to ContentView in "pick a budget" mode when an App Intent or Home Screen
//  quick action is triggered. ContentView observes pickBudgetForKind and shows the
//  budget list with a "Pick A Budget" header; tapping a row opens that budget and
//  presents the matching add sheet.
//

import Foundation

@MainActor
enum ShortcutRouter {
    static func openBudgetPicker(_ kind: AddSheetKind) {
        let nav = NavigationStateManager.shared
        nav.pendingItemTimestamp = nil
        nav.pendingYearMonth = nil
        nav.pickBudgetForKind = kind
        nav.navigationPath = []
        // navigationPath may already have been [] (e.g. re-triggering a quick action from
        // Home), in which case the assignment above is a no-op that wouldn't otherwise
        // dismiss a page pushed via navigationDestination(isPresented:)/(item:).
        nav.dismissPresentedPagesToken += 1
    }
}
