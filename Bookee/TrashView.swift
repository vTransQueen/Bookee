//
//  TrashView.swift
//  K Test
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
    @AppStorage("showFooters") private var showFooters: Bool = true
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
                } header: {
                    if !deletedItems.isEmpty {
                        Text("Items")
                    }
                } footer: {
                    if showFooters && !deletedItems.isEmpty && !isSelecting {
                        Text("Swipe right on a budget to restore it, or left to delete it.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            
            if deletedItems.isEmpty {
                EmptyStatePlaceholder(
                    systemImage: "trash",
                    title: "Trash is Empty",
                    message: "Deleted items will appear here and be kept for 30 days"
                )
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            trailingToolbarItem
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
        HStack {
            if isSelecting {
                SelectionIndicator(isSelected: selectedItems.contains(item.persistentModelID))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.trashDisplayName)
                    .font(.headline)
                
                if let daysLeft = item.daysUntilPermanentDeletion {
                    if daysLeft > 0 {
                        Text("Deletes in \(daysLeft) day\(daysLeft == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Deletes today")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            Spacer()
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
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .tint(.red)
        }
        .if(!isSelecting) { view in
            view
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        deleteAction = .singleItem(item)
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
                .disabled(deletedItems.isEmpty)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var bottomToolbarItem: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if isSelecting {
                Button {
                    guard !selectedItems.isEmpty else { return }
                    restoreSelectedItems()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(.primary)
                
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
            } else {
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
