//
//  ShortcutIntents.swift
//  Bookee
//
//  App Intents for adding budget items. Surfaces in the Shortcuts app, Siri, and Spotlight.
//  Each intent opens ContentView in "pick a budget" mode so the user can choose which
//  budget to add the item to before the add sheet is presented.
//

import AppIntents

// MARK: - Individual Intents

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Opens Bookee so you can pick a budget and add a new expense.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { ShortcutRouter.openBudgetPicker(.expense) }
        return .result()
    }
}

struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Income"
    static var description = IntentDescription("Opens Bookee so you can pick a budget and add a new income entry.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { ShortcutRouter.openBudgetPicker(.income) }
        return .result()
    }
}


struct AddBudgetPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Photo to Budget"
    static var description = IntentDescription("Opens Bookee so you can pick a budget and attach a photo.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { ShortcutRouter.openBudgetPicker(.photo) }
        return .result()
    }
}

struct AddBudgetFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Add File to Budget"
    static var description = IntentDescription("Opens Bookee so you can pick a budget and attach a file.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { ShortcutRouter.openBudgetPicker(.file) }
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct BookeeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: AddExpenseIntent(),
                phrases: [
                    "Add an expense in \(.applicationName)",
                    "New \(.applicationName) expense"
                ],
                shortTitle: "Add Expense",
                systemImageName: "cart"
            ),
            AppShortcut(
                intent: AddIncomeIntent(),
                phrases: [
                    "Add income in \(.applicationName)",
                    "New \(.applicationName) income"
                ],
                shortTitle: "Add Income",
                systemImageName: "dollarsign.circle"
            ),

            AppShortcut(
                intent: AddBudgetPhotoIntent(),
                phrases: [
                    "Add a photo in \(.applicationName)"
                ],
                shortTitle: "Add Photo",
                systemImageName: "photo"
            ),
            AppShortcut(
                intent: AddBudgetFileIntent(),
                phrases: [
                    "Add a file in \(.applicationName)"
                ],
                shortTitle: "Add File",
                systemImageName: "doc"
            ),
        ]
    }
}
