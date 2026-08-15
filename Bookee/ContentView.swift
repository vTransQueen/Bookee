//
//  ContentView.swift
//  K Test
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import UIKit
import SwiftData
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
    
    /// Tracks whether the user is in reordering mode
    /// Currently not actively used but maintained for potential future drag-and-drop features
    @State private var isReordering = false
    
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
    
    /// Tracks if the Settings view is currently being displayed
    /// Used to properly manage navigation state when returning from settings
    @State private var isCurrentlyViewingSettings = false
    
    /// User preference for app appearance (light, dark, or system)
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    /// User preference for date format display
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    
    /// User preference for how items should be sorted
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    
    /// User's name for personalized greeting
    @AppStorage("userName") private var userName: String = ""
    
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true
    
    // MARK: - Helper Methods (Persistence)
    
    /// Saves all pending changes in the model context to persistent storage
    private func persistContext() {
        modelContext.saveWithLogging("ContentView: Context saved successfully")
    }
    
    // MARK: - Computed Properties
    
    /// Returns all non-deleted items filtered and sorted based on user preference
    /// Supports manual ordering, date added, and date last opened sorting
    private var items: [Item] {
        let baseItems: [Item] = allNonDeletedItems
        switch sortOrder {
        case .manual:
            return baseItems.sorted { (item1: Item, item2: Item) -> Bool in
                item1.manualSortOrder < item2.manualSortOrder
            }
        case .dateAdded:
            return baseItems.sorted { (item1: Item, item2: Item) -> Bool in
                item1.timestamp > item2.timestamp
            }
        case .dateOpened:
            return baseItems.sorted { (item1: Item, item2: Item) -> Bool in
                item1.lastOpenedDate > item2.lastOpenedDate
            }
        }
    }
    

    
    /// Generates a personalized greeting based on current time and user's name
    /// Returns time-appropriate greeting (morning/afternoon/evening/night)
    /// Appends user's name if configured in settings
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        
        switch hour {
        case 0..<12:
            timeGreeting = "Good Morning"
        case 12..<17:
            timeGreeting = "Good Afternoon"
        case 17..<21:
            timeGreeting = "Good Evening"
        default:
            timeGreeting = "Good Night"
        }
        
        let trimmedName = userName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            return timeGreeting
        } else {
            return "\(timeGreeting), \(trimmedName)!"
        }
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
                        if !items.isEmpty {
                            Text("Budgets")
                        }
                    } footer: {
                        if showFooters && !items.isEmpty {
                            Text("Swipe right on a budget to duplicate or edit it, or left to delete it.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                
                // Empty state view - shown when there are no items
                if items.isEmpty {
                    VStack(spacing: 16) {
                        Text("Tap the + icon in the bottom right corner to add an item")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Routes navigation to individual item detail/budget pages
            .navigationDestination(for: Item.self) { item in
                // All items now route to Budget Visualizer (unified viewing experience)
                BudgetVisualizerPageView(
                    item: item,
                    navigationPath: $navigationStateManager.navigationPath
                )
                    .onAppear {
                        // Persist current item for state restoration
                        navigationStateManager.saveCurrentItem(item)
                    }
            }
            // Routes navigation to settings, trash, and backups screens
            .navigationDestination(for: String.self) { destination in
                Group {
                    if destination == "Settings" {
                        SettingsView()
                            .onAppear {
                                // Track that we're viewing settings for navigation state management
                                isCurrentlyViewingSettings = true
                                navigationStateManager.saveIsViewingSettings(true)
                            }
                    } else if destination == "Trash" {
                        TrashView()
                    } else if destination == "Backups" {
                        BackupsView()
                    }
                }
            }
            .toolbar {
                leadingToolbarItem
                trailingToolbarItem
                bottomToolbarItems
            }
            .onChange(of: navigationStateManager.navigationPath) { _, newPath in
                if !newPath.isEmpty && isSelecting {
                    isSelecting = false
                    selectedItems.removeAll()
                }
            }
            
            // Presents item detail editing sheet
            .sheet(isPresented: Binding(
                get: { selectedItemForEdit != nil },
                set: { if !$0 { 
                    // Cleanup when sheet is dismissed by swiping down or other gestures
                    if let item = selectedItemForEdit, isEditingDuplicatedItem {
                        // Delete unsaved duplicate items that user didn't save
                        modelContext.delete(item)
                        persistContext()
                        print("🗑️ Deleted cancelled duplicate item from database")
                    }
                    selectedItemForEdit = nil
                    isEditingDuplicatedItem = false
                    originalDuplicatedItemName = ""
                } }
            )) {
                if let item = selectedItemForEdit {
                    NavigationStack {
                        BudgetDetailsView(
                            item: item,
                            shouldFocusOnTitle: isEditingDuplicatedItem,
                            isEditingDuplicatedItem: isEditingDuplicatedItem,
                            originalDuplicatedItemName: originalDuplicatedItemName,
                            onSave: {
                                if isEditingDuplicatedItem {
                                    // Mark the item as saved so it appears in the main list
                                    item.isUnsavedDuplicate = false
                                    persistContext()
                                    print("💾 Item '\(item.name)' saved and now visible in list")
                                    
                                    // For new items, automatically navigate to their detail page
                                    if originalDuplicatedItemName.isEmpty {
                                        navigationStateManager.navigationPath.append(item)
                                    }
                                }
                                
                                selectedItemForEdit = nil
                                isEditingDuplicatedItem = false
                                originalDuplicatedItemName = ""
                            },
                            onCancel: {
                                // Delete unsaved duplicates when user cancels
                                if isEditingDuplicatedItem {
                                    modelContext.delete(item)
                                    persistContext()
                                    print("🗑️ Deleted cancelled duplicate item from database")
                                }
                                
                                selectedItemForEdit = nil
                                isEditingDuplicatedItem = false
                                originalDuplicatedItemName = ""
                            }
                        )
                    }
                    .standardSheetPresentation()
                    .interactiveDismissDisabled(isEditingDuplicatedItem)
                }
            }
            .onChange(of: selectedItemForEdit) { oldValue, newValue in
                // Persist sheet state changes for potential restoration
                navigationStateManager.saveEditingItem(newValue)
                if newValue != nil {
                    navigationStateManager.savePresentedSheet(.itemDetail)
                } else {
                    navigationStateManager.savePresentedSheet(nil)
                }
            }
            .onChange(of: navigationStateManager.navigationPath) { oldPath, newPath in
                // Clear saved state when user returns to root view
                if newPath.count == 0 {
                    navigationStateManager.saveCurrentItem(nil as Item?)
                    navigationStateManager.saveCurrentYearMonth(nil)
                    navigationStateManager.saveIsViewingSettings(false)
                    isCurrentlyViewingSettings = false
                } else if newPath.count == 1 && oldPath.count == 2 {
                    // User navigated back from MonthDetailsPageView to BudgetVisualizerPageView
                    navigationStateManager.saveCurrentYearMonth(nil)
                } else if isCurrentlyViewingSettings && newPath.count < oldPath.count {
                    // Detect when user navigates back from Settings
                    isCurrentlyViewingSettings = false
                    navigationStateManager.saveIsViewingSettings(false)
                }
            }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
        }
        // Apply user's color scheme preference (light/dark/system)
        .preferredColorScheme(appearanceMode.colorScheme)
        .background {
            AlertContainer {
                Color.clear
                    .alert(itemToDelete != nil ? "Delete Item?" : "Delete Selected Items?", isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { 
                            itemToDelete = nil
                        }
                        Button("Delete", role: .destructive) {
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
            // Log current data state for debugging
            print("📊 ContentView appeared")
            print("📊 Non-deleted items: \(allNonDeletedItems.count)")
            
            // Restore navigation state if app was relaunched
            if let pendingTimestamp = navigationStateManager.pendingItemTimestamp {
                print("📂 Restoring item from pending timestamp: \(pendingTimestamp)")
                if let item = navigationStateManager.resolveItem(from: pendingTimestamp, modelContext: modelContext),
                   item.deletedDate == nil {
                    navigationStateManager.navigationPath.append(item)
                    print("📂 ✅ Item restored to navigation path: \(item.name)")
                    
                    // Also restore month details if the user was viewing a specific month
                    if let yearMonth = navigationStateManager.pendingYearMonth {
                        navigationStateManager.navigationPath.append(yearMonth)
                        print("📂 ✅ Month details restored: \(yearMonth.month)/\(yearMonth.year)")
                    }
                }
                // Clear the pending restoration
                navigationStateManager.pendingItemTimestamp = nil
                navigationStateManager.pendingYearMonth = nil
            }
            
            // Note: Settings restoration is intentionally disabled to prevent visual glitches on app launch
        }
    }
    // MARK: - Toolbar Components
    
    /// Builds a row view for displaying an item in the list
    /// Displays item name, metadata, and appropriate controls based on current mode
    @ViewBuilder
    private func itemRow(for item: Item) -> some View {
        HStack(spacing: 0) {
            // Selection checkbox - appears in selection mode
            if isSelecting {
                SelectionIndicator(isSelected: selectedItems.contains(item.persistentModelID), highlightColor: highlightColor)
                    .padding(.trailing, 12)
            }
            
            // Main row content
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.headline)
                    // Display metadata based on current sort order
                    Text(sortOrder == .dateAdded ? 
                         "Date added: \(item.timestamp, format: dateFormat.styleWithTime)" :
                         "Last updated: \(item.lastModifiedDate, format: dateFormat.styleWithTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Navigation chevron - hidden in selection mode
                if !isSelecting {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            // Navigate to item detail when not in selection mode
            .if(!isSelecting) { view in
                view.onTapGesture {
                    navigationStateManager.navigationPath.append(item)
                }
            }
        }
        .contentShape(Rectangle())
        // Toggle selection when in selection mode
        .if(isSelecting) { view in
            view.onTapGesture {
                toggleSelection(for: item)
            }
        }
        // Show context menu with item actions when not selecting
        .if(!isSelecting) { view in
            view.contextMenu {
                Button {
                    duplicateItem(item)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                
                Button {
                    selectedItemForEdit = item
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    itemToDelete = item
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .tint(nil)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    itemToDelete = item
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    duplicateItem(item)
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .tint(.blue)
                Button {
                    selectedItemForEdit = item
                } label: {
                    Image(systemName: "pencil")
                }
                .tint(.blue)
            }
        }
    }
    
    /// Leading navigation bar button - always displays settings link
    @ToolbarContentBuilder
    private var leadingToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink(value: "Settings") {
                Label("Settings", systemImage: "gear")
            }
            .tint(.primary)
        }
    }
    
    /// Trailing toolbar items - changes based on selection mode
    /// Selection mode: Shows delete, select all/deselect all, and done buttons
    /// Normal mode: Shows select button
    @ToolbarContentBuilder
    private var trailingToolbarItem: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSelecting = false
                    selectedItems.removeAll()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.primary)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSelecting = true
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .tint(.primary)
                .disabled(items.isEmpty)
            }
        }
    }
    
    /// Bottom toolbar items - shows select all + delete in select mode, add item in normal mode
    @ToolbarContentBuilder
    private var bottomToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if isSelecting {
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
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            } else {
                Spacer()
                
                Button {
                    createBudgetVisualizer()
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .tint(.primary)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Toggles the selection state for a specific item
    /// Adds the item to the selection if not selected, removes it if already selected
    /// - Parameter item: The item to toggle selection for
    private func toggleSelection(for item: Item) {
        selectedItems.toggle(item.persistentModelID)
    }
    

    
    /// Reorders items in the list when user performs drag-to-reorder gesture
    /// Only functions when manual sort mode is active
    /// Updates the manualSortOrder property for all affected items
    /// - Parameters:
    ///   - source: The original indices of items being moved
    ///   - destination: The target index where items should be placed
    private func moveItems(from source: IndexSet, to destination: Int) {
        // Reordering only works in manual sort mode
        guard sortOrder == .manual else { return }
        
        // Create a mutable copy of the items array
        var revisedItems = items
        
        // Perform the reordering
        revisedItems.move(fromOffsets: source, toOffset: destination)
        
        // Update sort order values to reflect new positions
        for (index, item) in revisedItems.enumerated() {
            item.manualSortOrder = index
        }
        
        // Persist changes to database
        persistContext()
    }
    
    /// Soft-deletes all selected items by setting their deletedDate
    /// Items remain in database for potential recovery from trash
    /// Exits selection mode after deletion
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
    /// Item remains in database for potential recovery from trash
    /// - Parameter item: The item to mark as deleted
    private func deleteItem(_ item: Item) {
        item.deletedDate = Date()
        persistContext()
    }
    
    /// Creates a duplicate of an item with all its properties and data
    /// The duplicate is marked as unsaved and won't appear in the list until user confirms
    /// Opens the detail sheet automatically with focus on the title field
    /// User must change the name before the duplicate can be saved
    /// - Parameter item: The source item to duplicate
    private func duplicateItem(_ item: Item) {
        let baseName = item.displayName
        
        // Position duplicate at the top of the list (lowest sort order value)
        let minSortOrder = (items.min(by: { $0.manualSortOrder < $1.manualSortOrder })?.manualSortOrder ?? 0) - 1
        
        // Create new item with all properties copied from original
        let duplicatedItem = Item(
            timestamp: Date(),
            name: baseName,
            manualSortOrder: minSortOrder,
            taxSavingsPercentage: item.taxSavingsPercentage,
            isTaxSavingsEnabled: item.isTaxSavingsEnabled,
            itemType: item.itemType,
            targetYear: item.targetYear
        )
        
        // Copy additional settings
        duplicatedItem.lastTaxSavingsPercentage = item.lastTaxSavingsPercentage
        duplicatedItem.hideExpensesRow = item.hideExpensesRow
        duplicatedItem.hideTaxesGoalRow = item.hideTaxesGoalRow
        duplicatedItem.hideReallocationsRow = item.hideReallocationsRow
        duplicatedItem.hideIncomeSurplusRow = item.hideIncomeSurplusRow
        
        // Duplicate all budget data with new IDs
        if let data = item.decodeBudgetData() {
            duplicatedItem.expensesData    = try? JSONEncoder().encode(data.expenses.map    { $0.duplicate()  })
            duplicatedItem.incomesData     = try? JSONEncoder().encode(data.incomes.map     { $0.duplicate()  })
            duplicatedItem.attachmentsData = try? JSONEncoder().encode(data.attachments.map { $0.withNewID()  })
            
            // Reallocations require remapping linked-pair IDs together
            var idMapping: [UUID: UUID] = [:]
            let duplicatedReallocations = data.reallocations.map { r in
                let newId       = idMapping[r.id]       ?? { let id = UUID(); idMapping[r.id]       = id; return id }()
                let newLinkedId = idMapping[r.linkedId] ?? { let id = UUID(); idMapping[r.linkedId] = id; return id }()
                return Reallocation(id: newId, linkedId: newLinkedId, amount: r.amount,
                                    fromMonth: r.fromMonth, fromYear: r.fromYear,
                                    toMonth: r.toMonth, toYear: r.toYear,
                                    isFromEntry: r.isFromEntry, date: r.date, createdAt: r.createdAt)
            }
            duplicatedItem.reallocationsData = try? JSONEncoder().encode(duplicatedReallocations)
        }
        
        // Mark as unsaved - won't appear in list until user saves it
        duplicatedItem.isUnsavedDuplicate = true
        
        // Insert into context without persisting yet
        modelContext.insert(duplicatedItem)
        print("📝 Created duplicate item '\(baseName)' with all expenses, incomes, attachments, and reallocations (hidden until saved)")
        
        // Open detail sheet for name editing
        isEditingDuplicatedItem = true
        originalDuplicatedItemName = baseName
        selectedItemForEdit = duplicatedItem
    }
    
    /// Creates a new budget item and opens the detail sheet for configuration
    /// Item is marked as unsaved and won't appear in list until user provides a name
    /// New items start with default tax savings of 11% enabled
    private func createBudgetVisualizer() {
        // Position new item at the top of the list
        let minSortOrder = (items.min(by: { $0.manualSortOrder < $1.manualSortOrder })?.manualSortOrder ?? 0) - 1
        
        // Create item with empty name and default settings
        let newItem = Item(
            timestamp: Date(), 
            name: "", 
            manualSortOrder: minSortOrder, 
            taxSavingsPercentage: 11.0,
            isTaxSavingsEnabled: true,
            itemType: .budget
        )
        
        // Mark as unsaved - won't appear in list until given a name
        newItem.isUnsavedDuplicate = true
        
        // Insert into context without persisting yet
        modelContext.insert(newItem)
        print("📝 Created new budget item (hidden until saved)")
        
        // Open detail sheet with focus on title field
        isEditingDuplicatedItem = true
        originalDuplicatedItemName = ""
        selectedItemForEdit = newItem
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
