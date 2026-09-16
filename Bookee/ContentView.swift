//
//  ContentView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import UIKit
import SwiftData
import AppIntents
import UniformTypeIdentifiers
import PhotosUI

/// Main view that displays a list of all budget tracking items
/// Provides functionality to view, add, edit, duplicate, delete, reorder, and select items
/// Supports navigation to individual budget pages and app settings
struct ContentView: View {
    // MARK: - Properties
    
    /// SwiftData model context for database operations
    @Environment(\.modelContext) private var modelContext
    
    /// Query that fetches only non-deleted items from the database
    /// Items with deletedDate set are excluded from the main view and shown only in trash
    @Query(filter: #Predicate<Item> { $0.deletedDate == nil })
    private var rawNonDeletedItems: [Item]
    
    /// Computed property that filters out items marked as unsaved duplicates
    /// Unsaved duplicates are temporary items created during duplication/creation
    /// that haven't been confirmed by the user yet
    private var allNonDeletedItems: [Item] {
        rawNonDeletedItems.filter { !$0.isUnsavedDuplicate }
    }
    
    /// Tracks whether the user is in selection mode (for bulk actions)
    @State private var isSelecting = false

    /// Set of selected item IDs when in selection mode
    @State private var selectedItems = Set<PersistentIdentifier>()
    
    /// The item currently being edited in a detail sheet
    @State private var selectedItemForEdit: Item?
    
    /// Indicates if the item being edited is a newly created or duplicated item
    /// New/duplicated items require the user to change the title before saving
    @State private var isEditingDuplicatedItem = false
    
    /// Stores the original name of a duplicated item to validate that the user changed it
    /// Empty string for brand new items (which start with no name)
    @State private var originalDuplicatedItemName: String = ""
    
    /// Manages deletion confirmation alerts
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: Item?
    
    /// Singleton instance managing navigation state persistence across app launches
    /// Allows the app to restore the user's position when reopened
    @State private var navigationStateManager = NavigationStateManager.shared

    /// Tells the Budget Details page (pushed via editingItemBinding) to auto-open its
    /// nested Budget Trash page, when restoring a saved `.budgetDetailsTrash` subpage that
    /// was opened directly from Home. Reset once Details closes.
    @State private var restoreBudgetTrashOnDetails = false

    /// The in-progress edit, if any, to restore into the Budget Details page pushed via
    /// editingItemBinding, when Details was opened directly from Home rather than from
    /// within a budget's own page.
    @State private var restoreBudgetDetailsDraft: BudgetDetailsDraft?

    /// User preference for app appearance (light, dark, or system)
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    /// User preference for date format display
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    
    /// User preference for how items should be sorted
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    
    @HighlightColorStorage private var highlightColor

    // MARK: - Helper Methods (Persistence)
    
    /// Saves all pending changes in the model context to persistent storage
    private func persistContext() {
        modelContext.saveWithLogging("ContentView: Context saved successfully")
    }
    
    // MARK: - Computed Properties

    /// True when an App Intent or quick action is waiting for the user to choose a budget.
    private var isPickingBudget: Bool {
        navigationStateManager.pickBudgetForKind != nil
    }

    /// Returns all non-deleted items filtered and sorted based on user preference.
    /// In pick-a-budget mode only budget-type items are shown.
    private var items: [Item] {
        let baseItems: [Item] = isPickingBudget
            ? allNonDeletedItems.filter { $0.itemType == .budget }
            : allNonDeletedItems
        return sortedItems(baseItems, by: sortOrder)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good Morning!"
        case 12..<17: return "Good Afternoon!"
        case 17..<21: return "Good Evening!"
        default:      return "Good Night!"
        }
    }

    // Extracted binding to reduce body complexity for the Swift type-checker. Also covers
    // the case where the pushed Details page is popped by the system (back button/swipe)
    // rather than through onSave/onCancel — that path is normally blocked while editing an
    // unsaved duplicate (see BudgetDetailsView's navigationBarBackButtonHidden), but this
    // is a defensive backstop so a leaked duplicate can never linger in the database.
    private var editingItemBinding: Binding<Item?> {
        Binding(
            get: { selectedItemForEdit },
            set: { newValue in
                guard newValue == nil, let item = selectedItemForEdit else { return }
                if isEditingDuplicatedItem {
                    selectedItemForEdit = nil
                    isEditingDuplicatedItem = false
                    originalDuplicatedItemName = ""
                    // Defer the delete until after the pop animation finishes so
                    // BudgetDetailsView isn't reading a deleted SwiftData object
                    // while it's still sliding away.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        modelContext.delete(item)
                        persistContext()
                        print("🗑️ Deleted cancelled duplicate item from database")
                    }
                } else {
                    selectedItemForEdit = nil
                }
            }
        )
    }

    // MARK: - Body
    
    var body: some View {
        NavigationStack(path: $navigationStateManager.navigationPath) {
            ZStack {
                // Main list of items
                List {
                    Section {
                        ForEach(items) { item in
                            itemRow(for: item)
                        }
                        // Enable drag-to-reorder across all items
                        .onMove { source, destination in
                            moveItems(from: source, to: destination)
                        }
                    } header: {
                        Text(isPickingBudget ? "Pick A Budget" : greeting)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }
                .listStyle(.insetGrouped)
                .animation(.easeInOut(duration: 0.2), value: isSelecting)

                // Empty state view - shown when there are no items
                if items.isEmpty {
                    emptyStateView
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: NavDestination.self) { destination in
                switch destination {
                case .item(let item):
                    BudgetPageView(item: item)
                case .budgetTrash(let route):
                    BudgetTrashView(item: route.item)
                case .settings:
                    SettingsView()
                case .trash:
                    TrashView()
                case .backups:
                    BackupsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            NavigationStateManager.shared.showingUniversalSearch = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .tint(.primary)
                    .disabled(isPickingBudget)
                }
                trailingToolbarItem
                PageNavigationToolbarItem(label: "Home", systemImage: "house.fill", titleOnly: true, disabled: isPickingBudget)
                bottomToolbarItems
            }
            .onChange(of: navigationStateManager.navigationPath) { _, newPath in
                if !newPath.isEmpty && isSelecting {
                    isSelecting = false
                    selectedItems.removeAll()
                }
            }
            // Persists the full main-stack path on every change, regardless of where the
            // mutation originated (this view, NavigationStateManager.navigate, search, etc.).
            .onChange(of: navigationStateManager.navigationPath) { _, newPath in
                navigationStateManager.savePath(newPath)
            }
            .navigationDestination(item: editingItemBinding) { item in
                detailsDestination(for: item)
            }
            // Pages pushed via navigationDestination(isPresented:)/(item:) don't live in
            // navigationPath, so a path change alone doesn't dismiss them. When navigation
            // jumps to a destination that's already showing (e.g. Home while this Details
            // page is open), NavigationStateManager bumps this token so it gets popped too.
            .onChange(of: navigationStateManager.dismissPresentedPagesToken) { _, _ in
                editingItemBinding.wrappedValue = nil
            }
            .onChange(of: selectedItemForEdit) { oldValue, newValue in
                // Only persist once the item is actually saved — while editing a brand new
                // or duplicated item, isEditingDuplicatedItem is already true by the time
                // this fires, since both are set in the same tick.
                guard !isEditingDuplicatedItem else { return }
                navigationStateManager.saveSubpage(newValue != nil ? .budgetDetails : nil, for: newValue?.timestamp)
                if newValue == nil {
                    restoreBudgetTrashOnDetails = false
                    restoreBudgetDetailsDraft = nil
                }
            }
            .onChange(of: navigationStateManager.navigationPath) { oldPath, newPath in
                if newPath.count == 0 {
                    navigationStateManager.saveCurrentYearMonth(nil)
                    // ContentView.onAppear does not re-fire when popping back to the already-mounted
                    // root, so App Intent navigation (pendingItemTimestamp set by ShortcutRouter) must
                    // be consumed here instead. Deferred one tick to avoid mutating navigationPath
                    // inside an onChange(of: navigationPath) callback.
                    if let pendingTimestamp = navigationStateManager.pendingItemTimestamp {
                        Task { @MainActor in
                            restorePendingItem(pendingTimestamp)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Apply user's color scheme preference (light/dark/system)
        .preferredColorScheme(appearanceMode.colorScheme)
        .background {
            AlertContainer {
                Color.clear
                    .alert("Move to Trash?", isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) {
                            itemToDelete = nil
                        }
                        Button("Confirm", role: .destructive) {
                            if let item = itemToDelete {
                                deleteItem(item)
                                itemToDelete = nil
                            } else {
                                deleteSelectedItems()
                            }
                        }
                    } message: {
                        if let item = itemToDelete {
                            Text("This will move '\(item.displayName)' to the trash. You can restore it from the trash within 30 days.")
                        } else {
                            let count = selectedItems.count
                            let itemText = count == 1 ? "item" : "items"
                            Text("This will move \(count) \(itemText) to the trash. You can restore them from the trash within 30 days.")
                        }
                    }
            }
        }
        .onAppear {
            print("📊 ContentView appeared")
            print("📊 Non-deleted items: \(allNonDeletedItems.count)")
            restoreFullNavigationState()
            if let pendingTimestamp = navigationStateManager.pendingItemTimestamp {
                print("📂 Restoring item from pending timestamp: \(pendingTimestamp)")
                restoreItemOnAppear(pendingTimestamp)
            }
        }
    }

    // MARK: - Extracted Subviews

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text(isPickingBudget
                 ? "No budgets available."
                 : "Tap the + icon in the bottom right corner to add an item")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Pushed content for editing/creating a budget item. Extracted to keep `body` small.
    @ViewBuilder
    private func detailsDestination(for item: Item) -> some View {
        BudgetDetailsView(
            item: item,
            shouldFocusOnTitle: isEditingDuplicatedItem,
            isEditingDuplicatedItem: isEditingDuplicatedItem,
            originalDuplicatedItemName: originalDuplicatedItemName,
            restoreBudgetTrash: $restoreBudgetTrashOnDetails,
            initialDraft: $restoreBudgetDetailsDraft,
            onSave: {
                if isEditingDuplicatedItem {
                    item.isUnsavedDuplicate = false
                    persistContext()
                    print("💾 Item '\(item.name)' saved and now visible in list")
                    let shouldNavigateToNewItem = originalDuplicatedItemName.isEmpty
                    selectedItemForEdit = nil
                    isEditingDuplicatedItem = false
                    originalDuplicatedItemName = ""
                    if shouldNavigateToNewItem {
                        // Defer the push until after this page's own pop animation
                        // finishes — pushing in the same tick as the pop isn't reliable.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            navigationStateManager.navigationPath.append(.item(item))
                        }
                    }
                } else {
                    selectedItemForEdit = nil
                    isEditingDuplicatedItem = false
                    originalDuplicatedItemName = ""
                }
            },
            onCancel: {
                if isEditingDuplicatedItem {
                    selectedItemForEdit = nil
                    isEditingDuplicatedItem = false
                    originalDuplicatedItemName = ""
                    // Defer the delete until after the pop animation finishes so
                    // BudgetDetailsView isn't reading a deleted SwiftData object
                    // while it's still sliding away.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        modelContext.delete(item)
                        persistContext()
                        print("🗑️ Deleted cancelled duplicate item from database")
                    }
                } else {
                    selectedItemForEdit = nil
                    isEditingDuplicatedItem = false
                    originalDuplicatedItemName = ""
                }
            }
        )
    }

    // MARK: - Restoration Helpers

    @MainActor
    private func restorePendingItem(_ pendingTimestamp: Date) {
        let resolved = navigationStateManager.resolveItem(from: pendingTimestamp, modelContext: modelContext)
        if let item = resolved, item.deletedDate == nil {
            navigationStateManager.navigationPath.append(.item(item))
        }
        navigationStateManager.pendingItemTimestamp = nil
        navigationStateManager.pendingYearMonth = nil
    }

    private func restoreItemOnAppear(_ pendingTimestamp: Date) {
        if let item = navigationStateManager.resolveItem(from: pendingTimestamp, modelContext: modelContext),
           item.deletedDate == nil {
            navigationStateManager.navigationPath.append(.item(item))
            print("📂 ✅ Item restored to navigation path: \(item.name)")
            if let yearMonth = navigationStateManager.pendingYearMonth {
                NavigationStateManager.shared.viewedYearMonths[item.timestamp] = yearMonth
                print("📂 ✅ Month carousel focus restored: \(yearMonth.month)/\(yearMonth.year)")
            }
        }
        navigationStateManager.pendingItemTimestamp = nil
        navigationStateManager.pendingYearMonth = nil
    }

    /// Rebuilds the full saved navigation stack (Settings, Home Trash, Backups, a budget's
    /// Trash, and/or a budget item) on cold launch. Distinct from restoreItemOnAppear/
    /// restorePendingItem above, which handle the separate App Intent / quick-action flow.
    private func restoreFullNavigationState() {
        if let savedPath = navigationStateManager.pendingRestorePath {
            navigationStateManager.pendingRestorePath = nil
            let resolved = navigationStateManager.resolvePath(savedPath, modelContext: modelContext)
            if !resolved.isEmpty, case .item(let item) = resolved.last! {
                navigationStateManager.navigationPath = resolved
                if let yearMonth = navigationStateManager.pendingRestoreYearMonth {
                    navigationStateManager.viewedYearMonths[item.timestamp] = yearMonth
                }
                navigationStateManager.pendingRestoreYearMonth = nil
                // If the saved subpage belongs to the item now at the top of the stack, leave
                // it for that item's BudgetPageView instance to consume on its own appear
                // rather than consuming it here.
                if let pending = navigationStateManager.pendingSubpageRestore, pending.itemTimestamp == item.timestamp {
                    return
                }
                consumeTopLevelSubpageRestoreIfNeeded()
                return
            } else if !resolved.isEmpty {
                navigationStateManager.navigationPath = resolved
            }
        }
        // The saved path was empty/unresolvable (e.g. Home, or the saved item no longer
        // exists) — a saved Details/Details-Trash subpage in this state can only have been
        // opened directly from Home, so consume it here.
        navigationStateManager.pendingRestoreYearMonth = nil
        consumeTopLevelSubpageRestoreIfNeeded()
    }

    /// Restores a saved Budget Details (or nested Budget Trash) page that was opened
    /// directly from Home rather than from within a budget's own page.
    private func consumeTopLevelSubpageRestoreIfNeeded() {
        guard let pending = navigationStateManager.pendingSubpageRestore else { return }
        navigationStateManager.pendingSubpageRestore = nil
        guard let item = navigationStateManager.resolveItem(from: pending.itemTimestamp, modelContext: modelContext),
              item.deletedDate == nil, !item.isUnsavedDuplicate else { return }
        withoutAnimation {
            switch pending.subpage {
            case .budgetDetails:
                if case .budgetDetails(let draft)? = navigationStateManager.loadDraft(for: item.timestamp) {
                    restoreBudgetDetailsDraft = draft
                }
                selectedItemForEdit = item
            case .budgetDetailsTrash:
                restoreBudgetTrashOnDetails = true
                if case .budgetDetails(let draft)? = navigationStateManager.loadDraft(for: item.timestamp) {
                    restoreBudgetDetailsDraft = draft
                }
                selectedItemForEdit = item
            default:
                break
            }
        }
    }

    // MARK: - Toolbar Components
    
    @ToolbarContentBuilder
    private var trailingToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isPickingBudget {
                Button {
                    navigationStateManager.pickBudgetForKind = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .tint(.primary)
            } else {
                Button {
                    NavigationStateManager.shared.navigate(to: .settings)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .tint(.primary)
            }
        }
    }
    
    /// Bottom toolbar items - shows select all + delete in select mode, add item in normal mode
    @ToolbarContentBuilder
    private var bottomToolbarItems: some ToolbarContent {
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation { isSelecting = false }
                    selectedItems.removeAll()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.primary)

                Spacer()

                let selectAllText = selectedItems.isEmpty ? "Select All" : (selectedItems.count == items.count ? "Deselect All" : "Select All")
                Button {
                    if selectedItems.count == items.count {
                        selectedItems.removeAll()
                    } else {
                        selectedItems = Set(items.map { $0.persistentModelID })
                    }
                } label: {
                    Label(selectAllText, systemImage: selectedItems.count == items.count ? "checklist.unchecked" : "checklist.checked")
                }
                .tint(.primary)

                Button(role: .destructive) {
                    if !selectedItems.isEmpty {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .tint(.red)
            }
        } else {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation { isSelecting = true }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .tint(.primary)
                .disabled(items.isEmpty || isPickingBudget)

                Spacer()

                Button {
                    createBudget()
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .tint(.primary)
                .disabled(isPickingBudget)
            }
        }
    }

    // MARK: - Item Row

    /// Builds a row view for displaying an item in the list
    /// Displays item name, metadata, and appropriate controls based on current mode
    @ViewBuilder
    private func itemRow(for item: Item) -> some View {
        HStack(spacing: 0) {
            // Selection checkbox - appears in selection mode
            if isSelecting {
                SelectionIndicator(isSelected: selectedItems.contains(item.persistentModelID), highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }

            // Main row content
            BudgetItemRowContent(item: item, dateFormat: dateFormat, sortOrder: sortOrder, showsChevron: !isSelecting)
                .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(for: item)
            } else if let kind = navigationStateManager.pickBudgetForKind {
                // User is picking a budget for a quick action — navigate and open the add sheet.
                let now = Date()
                navigationStateManager.pendingAddSheet = PendingAddSheet(itemTimestamp: item.timestamp, kind: kind)
                navigationStateManager.viewedYearMonths[item.timestamp] = YearMonth(year: now.year, month: now.month)
                navigationStateManager.pickBudgetForKind = nil
                navigationStateManager.navigationPath.append(.item(item))
            } else {
                navigationStateManager.navigationPath.append(.item(item))
            }
        }
        .contextMenu {
            if !isSelecting && !isPickingBudget {
                Button {
                    duplicateItem(item)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(.primary)

                Button {
                    selectedItemForEdit = item
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }
                .tint(.primary)

                Divider()

                Button(role: .destructive) {
                    itemToDelete = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
        .tint(nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting && !isPickingBudget {
                Button {
                    itemToDelete = item
                    showingDeleteConfirmation = true
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isSelecting && !isPickingBudget {
                Button {
                    duplicateItem(item)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(.blue)
                Button {
                    selectedItemForEdit = item
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Helper Methods

    /// Toggles the selection state for a specific item
    private func toggleSelection(for item: Item) {
        selectedItems.toggle(item.persistentModelID)
    }

    /// Reorders items in the list when user performs drag-to-reorder gesture
    private func moveItems(from source: IndexSet, to destination: Int) {
        guard sortOrder == .manual else { return }
        var revisedItems = items
        revisedItems.move(fromOffsets: source, toOffset: destination)
        for (index, item) in revisedItems.enumerated() {
            item.manualSortOrder = index
        }
        persistContext()
    }
    
    /// Soft-deletes all selected items by setting their deletedDate
    private func deleteSelectedItems() {
        for id in selectedItems {
            if let item = items.first(where: { $0.persistentModelID == id }) {
                item.deletedDate = Date()
            }
        }
        persistContext()
        selectedItems.removeAll()
        isSelecting = false
    }
    
    /// Soft-deletes a single item by setting its deletedDate
    private func deleteItem(_ item: Item) {
        item.deletedDate = Date()
        persistContext()
    }
    
    /// Creates a duplicate of an item with all its properties and data
    private func duplicateItem(_ item: Item) {
        let baseName = item.displayName
        let minSortOrder = (items.min(by: { $0.manualSortOrder < $1.manualSortOrder })?.manualSortOrder ?? 0) - 1
        
        let duplicatedItem = Item(
            timestamp: Date(),
            name: baseName,
            manualSortOrder: minSortOrder,
            taxSavingsPercentage: item.taxSavingsPercentage,
            isTaxSavingsEnabled: item.isTaxSavingsEnabled,
            itemType: item.itemType,
            targetYear: item.targetYear
        )
        
        duplicatedItem.lastTaxSavingsPercentage = item.lastTaxSavingsPercentage
        duplicatedItem.hideExpensesRow = item.hideExpensesRow
        duplicatedItem.hideTaxesGoalRow = item.hideTaxesGoalRow
        duplicatedItem.hideReallocationsRow = item.hideReallocationsRow
        duplicatedItem.hideIncomeSurplusRow = item.hideIncomeSurplusRow
        duplicatedItem.hideOtherIncomeRow = item.hideOtherIncomeRow
        duplicatedItem.hiddenFilterCategories = item.hiddenFilterCategories
        duplicatedItem.calendarWeekStartDay = item.calendarWeekStartDay

        if let data = item.decodeBudgetData() {
            // Incomes are copied first so expenses can remap reimbursedByIncomeId to the
            // copied income's new ID rather than losing the reimbursement link.
            let incomeCopies = data.incomes.map { $0.duplicateForBudgetCopy() }
            let incomeIDMap = Dictionary(
                zip(data.incomes.map(\.id), incomeCopies.map(\.id)),
                uniquingKeysWith: { first, _ in first }
            )
            let expenseCopies = data.expenses.map { $0.duplicateForBudgetCopy(incomeIDMap: incomeIDMap) }
            let attachmentCopies = data.attachments.map { $0.duplicateForBudgetCopy() }

            var reallocationIDMap: [UUID: UUID] = [:]
            let reallocationCopies = data.reallocations.map { $0.duplicateForBudgetCopy(idMap: &reallocationIDMap) }

            let odometerCopies = data.odometerReadings.map { $0.duplicateForBudgetCopy() }

            try? duplicatedItem.encodeBudgetData(
                expenses: expenseCopies,
                incomes: incomeCopies,
                attachments: attachmentCopies,
                reallocations: reallocationCopies,
                odometerReadings: odometerCopies
            )
        }

        duplicatedItem.isUnsavedDuplicate = true
        modelContext.insert(duplicatedItem)
        print("📝 Created duplicate item '\(baseName)' with all expenses, incomes, attachments, reallocations, and odometer readings (hidden until saved)")
        
        isEditingDuplicatedItem = true
        originalDuplicatedItemName = baseName
        selectedItemForEdit = duplicatedItem
    }
    
    /// Creates a new budget item and opens the detail sheet for configuration
    private func createBudget() {
        let minSortOrder = (items.min(by: { $0.manualSortOrder < $1.manualSortOrder })?.manualSortOrder ?? 0) - 1
        let newItem = Item(
            timestamp: Date(), 
            name: "", 
            manualSortOrder: minSortOrder, 
            taxSavingsPercentage: 11.0,
            isTaxSavingsEnabled: true,
            itemType: .budget
        )
        newItem.isUnsavedDuplicate = true
        modelContext.insert(newItem)
        print("📝 Created new budget item (hidden until saved)")
        isEditingDuplicatedItem = true
        originalDuplicatedItemName = ""
        selectedItemForEdit = newItem
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
