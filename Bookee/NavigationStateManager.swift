//
//  NavigationStateManager.swift
//  Bookee
//
//  Created by Kara Eveland on 3/14/26.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - App Page

enum AppPage: String, CaseIterable {
    case home = "Home"
    case settings = "Settings"
    case backups = "Backups"
    case trash = "Home Trash"

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .settings: return "gear"
        case .trash: return "trash"
        case .backups: return "externaldrive"
        }
    }
}

// MARK: - Budget Trash Route

/// Navigation destination for a specific budget item's trash view.
struct BudgetTrashRoute: Hashable {
    let item: Item
}

// MARK: - Pending Scroll Target

/// Identifies a specific transaction row to scroll to after search navigation.
/// Carrying the item timestamp ensures only the correct BudgetPageView acts on it.
struct PendingScrollTarget: Equatable {
    let itemTimestamp: Date
    let yearMonth: YearMonth
    let scrollID: String
}

// MARK: - Add Sheet Kind

enum AddSheetKind: String, Equatable {
    case expense, income, reallocation, photo, file
}

struct PendingAddSheet: Equatable {
    let itemTimestamp: Date
    let kind: AddSheetKind
}

// MARK: - Nav Destination

/// Typed enum covering every possible destination in the app's single NavigationStack.
/// Using a concrete array instead of the opaque NavigationPath lets navigate(to:) inspect
/// the stack directly, enabling dedup for all destination types (AppPages, Items, and
/// BudgetTrashRoutes) without a separate shadow structure.
enum NavDestination: Hashable {
    case settings
    case trash
    case backups
    case item(Item)
    case budgetTrash(BudgetTrashRoute)
}

// MARK: - Saved Nav Destination

/// Codable mirror of `NavDestination` for persistence. Items are identified by their
/// `timestamp` (same identity key used throughout navigation restoration) rather than by
/// holding onto the `Item` itself, since SwiftData model objects aren't Codable.
enum SavedNavDestination: Codable, Equatable {
    case settings
    case trash
    case backups
    case item(Date)
    case budgetTrash(Date)
}

// MARK: - Saved Subpage

/// Identifies a page pushed on top of a Budget page (or, for the Details cases, pushed
/// directly from Home) that should be restored after the main stack is rebuilt. Kept
/// separate from `SavedNavDestination` because these pages aren't part of navigationPath —
/// they're shown via `navigationDestination(isPresented:)`/`(item:)`.
enum SavedSubpage: Codable, Equatable {
    case budgetDetails
    case budgetDetailsTrash
    case income
    case incomeAttachment(UUID)
    case filter
    case attachment(UUID)
    // Row-triggered edit sheets. Expense/income carry the specific occurrence date tapped
    // (rather than always falling back to the recurring template's base date) so restoring
    // a recurring occurrence's edit sheet lands on the same occurrence the user had open.
    // Like the add cases below, the in-progress field values (including which attachment, if
    // any, was being viewed) are staged separately via AddSheetDraft/saveDraft(_:for:)/
    // loadDraft(for:), keyed by the same item timestamp.
    case editExpense(id: UUID, occurrenceDate: Date?)
    case editIncome(id: UUID, occurrenceDate: Date?)
    case editReallocation(id: UUID)
    case editOdometerReading(id: UUID)
    // Add sheets. Unlike the edit cases above, there's no existing model object to look up.
    case addExpense
    case addIncome
    case addReallocation
    case addOdometerReading
}

/// Ties a saved subpage to the budget item it belongs to, so only the matching
/// BudgetPageView (or ContentView, for the Home-opened Details cases) acts on it.
struct PendingSubpageRestore: Equatable {
    let itemTimestamp: Date
    let subpage: SavedSubpage
}

// MARK: - Add Sheet Draft

/// Snapshot of every user-entered field for the combined Add Expense/Income form (used by
/// both AddExpenseView and AddIncomeView, which share nearly identical state — the two
/// views differ only in which fields they surface and in `pickerSelectedMonth`, which only
/// AddIncomeView's month-selector mode uses).
struct TransactionFormDraft: Codable, Equatable {
    var name: String
    var amount: Decimal
    var date: Date
    var showDate: Bool
    var endDate: Date
    var showEndDate: Bool
    var isRecurring: Bool
    var recurringFrequency: RecurringFrequency
    var recurrenceRule: RecurrenceRule
    var isMonthlyPaymentPlan: Bool
    var totalAmount: Decimal
    var numberOfPayments: Int
    var isTaxable: Bool
    var itemType: AddItemType
    var attachments: [Attachment]
    var selectedCategories: Set<String>
    var pickerSelectedMonth: Int?
    // The attachment (by id, looked up in `attachments` above) whose viewer was open on top
    // of this form, if any.
    var viewingAttachmentID: UUID?
}

/// Snapshot of every user-entered field for ReallocateFundsView.
struct ReallocationFormDraft: Codable, Equatable {
    var amount: Decimal
    var fromDate: Date
    var toDate: Date
    var attachments: [Attachment]
    var viewingAttachmentID: UUID?
}

/// Snapshot of every user-entered field for AddOdometerReadingView.
struct OdometerReadingFormDraft: Codable, Equatable {
    var vehicle: String
    var odometerValue: Int?
    var date: Date
    var selectedCategories: Set<String>
    var attachments: [Attachment]
    var viewingAttachmentID: UUID?
}

/// Snapshot of every user-entered field for BudgetDetailsView (the Add/Edit Budget page).
struct BudgetDetailsDraft: Codable, Equatable {
    var name: String
    var taxSavingsPercentage: Double
    var isTaxSavingsEnabled: Bool
    var lastTaxSavingsPercentage: Double
    var calendarWeekStartDay: Int
}

/// The in-progress data for whichever Add or Edit sheet is currently open (including Add/Edit
/// Budget), staged for restoration after the app is relaunched while the user is still
/// filling out a new — or editing an existing — expense/income/reallocation/odometer
/// reading/budget. Reused for both Add and Edit sheets sharing the same field shape (e.g.
/// `.reallocation` covers both ReallocateFundsView and EditReallocateFundsView) since only
/// one sheet can be open anywhere in the app at a time, so a single slot (rather than one per
/// item) is enough. Cleared only when the user explicitly taps Save or an explicit cancel/
/// dismiss button — navigating away by any other means (search, a quick action, killing the
/// app) preserves it so the same in-progress form reopens with everything intact.
enum AddSheetDraft: Codable, Equatable {
    case expenseOrIncome(TransactionFormDraft)
    case reallocation(ReallocationFormDraft)
    case odometerReading(OdometerReadingFormDraft)
    case budgetDetails(BudgetDetailsDraft)
}

private struct SavedAddSheetDraft: Codable {
    let itemTimestamp: Date
    let draft: AddSheetDraft
}

// MARK: - Navigation State Manager

/// Manages the persistence and restoration of navigation state across app launches.
/// Uses UserDefaults to store navigation state and item timestamps as unique identifiers.
@Observable
class NavigationStateManager {
    /// Shared singleton instance
    static let shared = NavigationStateManager()
    
    /// The current navigation path (not persisted to UserDefaults)
    var navigationPath: [NavDestination] = []
    
    /// Pending item timestamp to be resolved when ModelContext becomes available.
    /// Set at runtime by App Intents / Home Screen quick actions (ShortcutRouter) — distinct
    /// from `pendingRestorePath` below, which handles cold-launch persistence restoration.
    var pendingItemTimestamp: Date?

    /// Pending year-month to be pushed after item restoration (paired with pendingItemTimestamp)
    var pendingYearMonth: YearMonth?

    /// The full saved navigation stack to restore on cold launch, resolved to real Items by
    /// ContentView once ModelContext is available. Cleared once consumed.
    var pendingRestorePath: [SavedNavDestination]?

    /// The year-month to focus if the restored path's last destination is a budget item.
    var pendingRestoreYearMonth: YearMonth?

    /// A page pushed on top of a budget item (or Home) to restore once its owning view
    /// mounts. Consumed by BudgetPageView for nested cases, or by ContentView directly when
    /// Details was opened from Home.
    var pendingSubpageRestore: PendingSubpageRestore?

    /// The year-month last actively viewed per budget item (not persisted), keyed by item.timestamp.
    /// Updated by BudgetPageView as the user scrolls months; read and cleared on first appear
    /// so each budget independently remembers its carousel position.
    var viewedYearMonths: [Date: YearMonth] = [:]

    /// Controls visibility of the universal search overlay.
    var showingUniversalSearch = false

    /// The current universal search query. Persists for the lifetime of the process so
    /// results are restored when the search overlay is reopened. Cleared on full app quit.
    var universalSearchText: String = ""

    /// Scroll target set by search navigation. BudgetPageView reads this on appear
    /// (or onChange if the view is already mounted) to jump to the correct month and row.
    var pendingScrollTarget: PendingScrollTarget?

    /// Set by App Intents / Home Screen quick actions to open an add sheet in BudgetPageView.
    var pendingAddSheet: PendingAddSheet?

    /// Set by search navigation to open the Budget Details sheet once BudgetPageView for the
    /// matching item is mounted (mirrors pendingScrollTarget/pendingAddSheet).
    var pendingBudgetDetailsTimestamp: Date?

    /// Set by the AppDelegate on cold launch from a Home Screen quick action.
    var pendingQuickActionKind: AddSheetKind?

    /// Set by ShortcutRouter when the user launched a quick action or intent and should
    /// pick a budget from ContentView's list before the add sheet is presented.
    var pickBudgetForKind: AddSheetKind?

    /// Bumped whenever navigation jumps to a destination that is already showing (jumpTo's
    /// early-return case) or the budget picker is reopened on an already-empty path. Pages
    /// pushed via `navigationDestination(isPresented:)`/`(item:)` don't live in navigationPath,
    /// so changing the path alone doesn't dismiss them; views watch this token instead to reset
    /// their own show flags and edit targets.
    var dismissPresentedPagesToken = 0

    /// UserDefaults key for storing the serialized navigation state
    static let navigationStateKey = "savedNavigationState"

    private var cachedState: NavigationState?

    private init() {
        // During initialization, decode the saved navigation state and stage it for
        // ContentView to resolve into real Items once ModelContext is available.
        guard let data = UserDefaults.standard.data(forKey: Self.navigationStateKey),
              let state = try? JSONDecoder().decode(NavigationState.self, from: data) else {
            print("📂 No saved navigation state - showing fresh app")
            return
        }
        cachedState = state

        if let path = state.path {
            // `path` was explicitly saved under the new scheme — even an empty array means
            // Home was saved on purpose, so there's nothing to restore. Only fall back to the
            // legacy single-item field when `path` itself was never written at all.
            if !path.isEmpty {
                pendingRestorePath = path
            }
        } else if let legacyTimestamp = state.currentItemTimestamp {
            // Fallback for state saved before full-stack restoration existed.
            pendingRestorePath = [.item(legacyTimestamp)]
        }
        pendingRestoreYearMonth = state.currentYearMonth

        if let subpage = state.subpage, let subpageTimestamp = state.subpageItemTimestamp {
            pendingSubpageRestore = PendingSubpageRestore(itemTimestamp: subpageTimestamp, subpage: subpage)
        }

        print("📂 Navigation state restoration prepared")
    }

    // MARK: - State Persistence

    /// Loads the stored state, applies `update`, then re-saves it atomically.
    /// The decoded state is kept in `cachedState` so subsequent calls skip the JSON decode.
    private func updateState(_ update: (inout NavigationState) -> Void) {
        var state: NavigationState
        if let cached = cachedState {
            state = cached
        } else if let data = UserDefaults.standard.data(forKey: Self.navigationStateKey),
                  let decoded = try? JSONDecoder().decode(NavigationState.self, from: data) {
            state = decoded
        } else {
            state = NavigationState()
        }
        update(&state)
        cachedState = state
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: Self.navigationStateKey)
        }
    }

    /// Legacy method that logs navigation state persistence.
    func saveNavigationState(modelContext: ModelContext) {
        print("💾 Navigation state persisted to UserDefaults")
    }

    /// Saves the full main-stack navigation path, mapped to its Codable equivalent.
    func savePath(_ path: [NavDestination]) {
        updateState { state in
            state.path = path.map { dest in
                switch dest {
                case .settings: return .settings
                case .trash: return .trash
                case .backups: return .backups
                case .item(let item): return .item(item.timestamp)
                case .budgetTrash(let route): return .budgetTrash(route.item.timestamp)
                }
            }
        }
    }

    /// Saves the page currently pushed on top of a budget item (or Home, for Details opened
    /// from the item list). Pass `nil` to clear it when the page is dismissed.
    func saveSubpage(_ subpage: SavedSubpage?, for itemTimestamp: Date?) {
        updateState { state in
            state.subpage = subpage
            state.subpageItemTimestamp = subpage != nil ? itemTimestamp : nil
        }
    }

    func saveCurrentYearMonth(_ yearMonth: YearMonth?) {
        updateState { $0.currentYearMonth = yearMonth }
        print("💾 Current year-month saved: \(yearMonth.map { "\($0.month)/\($0.year)" } ?? "nil")")
    }

    // MARK: - Add Sheet Draft Persistence

    /// UserDefaults key for the single in-progress Add sheet draft, if any.
    private static let addSheetDraftKey = "savedAddSheetDraft"

    /// Overwrites the single draft slot. Called continuously (debounced) as the user types
    /// into whichever Add sheet is open.
    func saveDraft(_ draft: AddSheetDraft, for itemTimestamp: Date) {
        let saved = SavedAddSheetDraft(itemTimestamp: itemTimestamp, draft: draft)
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: Self.addSheetDraftKey)
        }
    }

    /// Returns the saved draft only if it belongs to `itemTimestamp`, so a stale draft left
    /// over for a different budget is never mistakenly applied.
    func loadDraft(for itemTimestamp: Date) -> AddSheetDraft? {
        guard let data = UserDefaults.standard.data(forKey: Self.addSheetDraftKey),
              let saved = try? JSONDecoder().decode(SavedAddSheetDraft.self, from: data),
              saved.itemTimestamp == itemTimestamp else { return nil }
        return saved.draft
    }

    /// Clears the draft slot. Called when the user explicitly taps Save or an explicit
    /// cancel/dismiss button, and when a fresh (non-restored) Add sheet is opened, so a
    /// previously abandoned draft is never mistakenly reused by an unrelated new attempt.
    func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.addSheetDraftKey)
    }

    // MARK: - State Restoration

    /// Resolves a saved path (item/budgetTrash entries carry a timestamp instead of an Item)
    /// back into real `NavDestination`s, fetching items once up front. Stops at the first
    /// entry whose item is missing, trashed, or an unsaved duplicate so the restored stack
    /// never has a gap or lands on a page that no longer exists.
    func resolvePath(_ savedPath: [SavedNavDestination], modelContext: ModelContext) -> [NavDestination] {
        let descriptor = FetchDescriptor<Item>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return [] }
        func resolveValidItem(timestamp: Date) -> Item? {
            allItems.first { $0.timestamp == timestamp && $0.deletedDate == nil && !$0.isUnsavedDuplicate }
        }

        var resolved: [NavDestination] = []
        for dest in savedPath {
            switch dest {
            case .settings: resolved.append(.settings)
            case .trash: resolved.append(.trash)
            case .backups: resolved.append(.backups)
            case .item(let timestamp):
                guard let item = resolveValidItem(timestamp: timestamp) else { return resolved }
                resolved.append(.item(item))
            case .budgetTrash(let timestamp):
                guard let item = resolveValidItem(timestamp: timestamp) else { return resolved }
                resolved.append(.budgetTrash(BudgetTrashRoute(item: item)))
            }
        }
        return resolved
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
    
    // MARK: - Navigation

    /// Navigates to a top-level app page at its canonical location in the hierarchy.
    /// Home clears the stack. Settings lands at [settings]. Trash and Backups land
    /// at [settings, destination] since they live inside Settings.
    func navigate(to page: AppPage) {
        switch page {
        case .home:
            jumpTo([])
        case .settings:
            jumpTo([.settings])
        case .trash:
            jumpTo([.settings, .trash])
        case .backups:
            jumpTo([.settings, .backups])
        }
    }

    /// Navigates to a budget item page at its canonical location (direct child of Home).
    func navigateToItem(_ item: Item) {
        jumpTo([.item(item)])
    }

    /// Navigates directly to a specific budget's own trash view (a top-level destination,
    /// not nested under that budget's page).
    func navigateToBudgetTrash(_ item: Item) {
        jumpTo([.budgetTrash(BudgetTrashRoute(item: item))])
    }

    /// Navigates to the destination path.
    ///
    /// - Already at the destination: no-op (dedup).
    /// - Current path is a prefix of the target: push only the missing steps forward.
    /// - Target's final destination is already in the stack: pop back to it.
    /// - Otherwise: navigate directly to the new path.
    private func jumpTo(_ path: [NavDestination]) {
        guard navigationPath != path else {
            dismissPresentedPagesToken += 1
            return
        }

        // Already partway there — push only the remaining steps
        if !navigationPath.isEmpty && path.starts(with: navigationPath) {
            withAnimation {
                for dest in path.dropFirst(navigationPath.count) {
                    navigationPath.append(dest)
                }
            }
            return
        }

        // Destination is already in the stack — pop back to it
        if let target = path.last, let idx = navigationPath.lastIndex(of: target) {
            withAnimation { navigationPath = Array(navigationPath.prefix(idx + 1)) }
            return
        }

        // Navigate directly
        withAnimation { navigationPath = path }
    }

    /// Navigates back one page in the stack. No-op if already at the root.
    func goBack() {
        guard !navigationPath.isEmpty else { return }
        withAnimation { navigationPath = Array(navigationPath.dropLast()) }
    }

}

// MARK: - Navigation State Model

/// Codable structure representing the complete navigation state of the app.
/// Persisted to UserDefaults and restored on app launch.
struct NavigationState: Codable {
    /// Legacy single-item identifier, kept only as a fallback for state saved before
    /// full-stack restoration existed (see NavigationStateManager.init). No longer written.
    var currentItemTimestamp: Date?

    /// The full main-stack navigation path (Settings, Home Trash, Backups, a budget's Trash,
    /// and/or a budget item), in order from the root.
    var path: [SavedNavDestination]?

    /// A page pushed on top of the last entry in `path` (or on top of Home, for Details
    /// opened directly from the item list), to be restored once its owning view mounts.
    var subpage: SavedSubpage?

    /// The budget item `subpage` belongs to.
    var subpageItemTimestamp: Date?

    /// The currently viewed year-month in the month details page, if any
    var currentYearMonth: YearMonth?
}
