//
//  TrashView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/18/26.
//

import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Item> { item in
        item.deletedDate != nil
    }, sort: \Item.deletedDate, order: .reverse) private var deletedItems: [Item]
    
    @State private var isSelecting = false
    @State private var selectedItems = Set<PersistentIdentifier>()
    @State private var showingDeleteConfirmation = false
    @State private var deleteAction: DeleteAction = .emptyTrash
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @HighlightColorStorage private var highlightColor
    
    // Tracks which deletion operation triggered the confirmation alert
    private enum DeleteAction {
        case emptyTrash
        case singleItem(Item)
        case selectedItems
        
        var title: String {
            switch self {
            case .emptyTrash: return "Empty Trash?"
            case .singleItem: return "Delete Item?"
            case .selectedItems: return "Delete Selected Items?"
            }
        }
        
        func message(deletedItemsCount: Int, selectedItemsCount: Int) -> String {
            switch self {
            case .emptyTrash:
                return "This will permanently delete all \(deletedItemsCount) item\(deletedItemsCount == 1 ? "" : "s") in the trash. This action cannot be undone."
            case .singleItem(let item):
                return "This will permanently delete '\(item.trashDisplayName)'. This action cannot be undone."
            case .selectedItems:
                return "This will permanently delete \(selectedItemsCount) item\(selectedItemsCount == 1 ? "" : "s"). This action cannot be undone."
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .emptyTrash: return "Empty Trash"
            case .singleItem: return "Delete"
            case .selectedItems: return "Delete"
            }
        }
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(deletedItems) { item in
                        itemRow(for: item)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.easeInOut(duration: 0.2), value: isSelecting)

            if deletedItems.isEmpty {
                EmptyStatePlaceholder(
                    systemImage: "trash",
                    title: "Trash is Empty",
                    message: "Deleted items will appear here and be kept for 30 days"
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            PageNavigationToolbarItem(label: "Home Trash", systemImage: "trash", titleOnly: true)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { NavigationStateManager.shared.showingUniversalSearch = true } } label: {
                    Image(systemName: "magnifyingglass")
                }
                .tint(.primary)
            }
            bottomToolbarItem
        }
        .background {
            // AlertContainer applies primary tint to ensure alerts use standard system colors
            AlertContainer {
                Color.clear
                    .alert(deleteAction.title, isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button(deleteAction.buttonTitle, role: .destructive) {
                            performDelete()
                        }
                    } message: {
                        Text(deleteAction.message(deletedItemsCount: deletedItems.count, selectedItemsCount: selectedItems.count))
                    }
            }
        }
    }
    
    @ViewBuilder
    private func itemRow(for item: Item) -> some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: selectedItems.contains(item.persistentModelID), highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }

            BudgetItemRowContent(
                item: item,
                dateFormat: dateFormat,
                sortOrder: sortOrder,
                nameOverride: item.trashDisplayName,
                showsChevron: false,
                trashDaysLeft: item.daysUntilPermanentDeletion
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(for: item)
            }
        }
        .contextMenu {
            Button {
                restoreItem(item)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.primary)
            
            Divider()
            
            Button(role: .destructive) {
                deleteAction = .singleItem(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    deleteAction = .singleItem(item)
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    restoreItem(item)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
    }
    
    // MARK: - Toolbar Components

    
    @ToolbarContentBuilder
    private var bottomToolbarItem: some ToolbarContent {
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation { isSelecting = false }
                    selectedItems.removeAll()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.primary)

                Button {
                    restoreSelectedItems()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(.primary)
                .disabled(selectedItems.isEmpty)

                Spacer()

                let selectAllText = selectedItems.isEmpty ? "Select All" : (selectedItems.count == deletedItems.count ? "Deselect All" : "Select All")
                Button {
                    guard !deletedItems.isEmpty else { return }
                    if selectedItems.count == deletedItems.count {
                        selectedItems.removeAll()
                    } else {
                        selectedItems = Set(deletedItems.map { $0.persistentModelID })
                    }
                } label: {
                    Label(selectAllText, systemImage: selectedItems.count == deletedItems.count ? "checklist.unchecked" : "checklist.checked")
                }
                .tint(.primary)

                Button(role: .destructive) {
                    guard !selectedItems.isEmpty else { return }
                    deleteAction = .selectedItems
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
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
                .disabled(deletedItems.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    guard !deletedItems.isEmpty else { return }
                    deleteAction = .emptyTrash
                    showingDeleteConfirmation = true
                } label: {
                    Label("Empty Trash", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performDelete() {
        switch deleteAction {
        case .emptyTrash:
            emptyTrash()
        case .singleItem(let item):
            permanentlyDeleteItem(item)
        case .selectedItems:
            permanentlyDeleteSelectedItems()
        }
    }
    
    private func persistContext(label: String) {
        modelContext.saveWithLogging("TrashView: \(label)")
    }

    private func toggleSelection(for item: Item) {
        selectedItems.toggle(item.persistentModelID)
    }
    
    private func restoreItem(_ item: Item) {
        item.deletedDate = nil
        persistContext(label: "Restored 1 item")
    }
    
    private func restoreSelectedItems() {
        let count = selectedItems.count
        for id in selectedItems {
            if let item = deletedItems.first(where: { $0.persistentModelID == id }) {
                item.deletedDate = nil
            }
        }
        persistContext(label: "Restored \(count) item(s)")
        selectedItems.removeAll()
        isSelecting = false
    }
    
    private func permanentlyDeleteItem(_ item: Item) {
        modelContext.delete(item)
        persistContext(label: "Permanently deleted 1 item")
    }
    
    private func permanentlyDeleteSelectedItems() {
        let count = selectedItems.count
        for id in selectedItems {
            if let item = deletedItems.first(where: { $0.persistentModelID == id }) {
                modelContext.delete(item)
            }
        }
        persistContext(label: "Permanently deleted \(count) item(s)")
        selectedItems.removeAll()
        isSelecting = false
    }
    
    private func emptyTrash() {
        let count = deletedItems.count
        for item in deletedItems {
            modelContext.delete(item)
        }
        persistContext(label: "Emptied trash (\(count) item(s))")
    }
}

#Preview {
    TrashView()
        .modelContainer(for: Item.self, inMemory: true)
}
