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
    @Query(filter: #Predicate<Book> { $0.deletedDate != nil },
           sort: \Book.deletedDate,
           order: .reverse)
    private var deletedBooks: [Book]

    @State private var isSelecting = false
    @State private var selectedBooks = Set<PersistentIdentifier>()
    @State private var showingDeleteConfirmation = false
    @State private var deleteAction: DeleteAction = .emptyTrash
    @AppStorage("showFooters") private var showFooters: Bool = true
    @HighlightColorStorage private var highlightColor

    private enum DeleteAction {
        case emptyTrash
        case singleBook(Book)
        case selectedBooks

        var title: String {
            switch self {
            case .emptyTrash: return "Empty Trash?"
            case .singleBook: return "Delete Book?"
            case .selectedBooks: return "Delete Selected Books?"
            }
        }

        func message(count: Int, selectedCount: Int) -> String {
            switch self {
            case .emptyTrash:
                return "This will permanently delete all \(count) book\(count == 1 ? "" : "s") in the trash. This action cannot be undone."
            case .singleBook(let book):
                return "This will permanently delete '\(book.displayTitle)'. This action cannot be undone."
            case .selectedBooks:
                return "This will permanently delete \(selectedCount) book\(selectedCount == 1 ? "" : "s"). This action cannot be undone."
            }
        }

        var buttonTitle: String {
            switch self {
            case .emptyTrash: return "Empty Trash"
            case .singleBook, .selectedBooks: return "Delete"
            }
        }
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(deletedBooks) { book in
                        bookRow(for: book)
                    }
                } header: {
                    if !deletedBooks.isEmpty { Text("Books") }
                } footer: {
                    if showFooters && !deletedBooks.isEmpty && !isSelecting {
                        Text("Swipe right on a book to restore it, or left to delete it.")
                    }
                }
            }
            .listStyle(.insetGrouped)

            if deletedBooks.isEmpty {
                EmptyStatePlaceholder(
                    systemImage: "trash",
                    title: "Trash is Empty",
                    message: "Deleted books will appear here and be kept for 30 days"
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
            AlertContainer {
                Color.clear
                    .alert(deleteAction.title, isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button(deleteAction.buttonTitle, role: .destructive) { performDelete() }
                    } message: {
                        Text(deleteAction.message(count: deletedBooks.count, selectedCount: selectedBooks.count))
                    }
            }
        }
    }

    @ViewBuilder
    private func bookRow(for book: Book) -> some View {
        HStack {
            if isSelecting {
                SelectionIndicator(isSelected: selectedBooks.contains(book.persistentModelID))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(book.displayTitle).font(.headline)
                if !book.author.isEmpty {
                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                }
                if let daysLeft = book.daysUntilPermanentDeletion {
                    Text(daysLeft > 0 ? "Deletes in \(daysLeft) day\(daysLeft == 1 ? "" : "s")" : "Deletes today")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { if isSelecting { toggleSelection(for: book) } }
        .contextMenu {
            Button { restoreBook(book) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Divider()
            Button(role: .destructive) {
                deleteAction = .singleBook(book)
                showingDeleteConfirmation = true
            } label: { Label("Delete Permanently", systemImage: "trash") }
        }
        .if(!isSelecting) { view in
            view
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { deleteAction = .singleBook(book); showingDeleteConfirmation = true } label: {
                        Image(systemName: "trash")
                    }.tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { restoreBook(book) } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }.tint(.blue)
                }
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbarItem: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSelecting = false; selectedBooks.removeAll() } label: {
                    Label("Done", systemImage: "checkmark")
                }.tint(.primary)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSelecting = true } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }.tint(.primary).disabled(deletedBooks.isEmpty)
            }
        }
    }

    @ToolbarContentBuilder
    private var bottomToolbarItem: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if isSelecting {
                Button { guard !selectedBooks.isEmpty else { return }; restoreSelectedBooks() } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }.tint(.primary)
                Spacer()
                let selectAllText = selectedBooks.count == deletedBooks.count ? "Deselect All" : "Select All"
                Button {
                    if selectedBooks.count == deletedBooks.count {
                        selectedBooks.removeAll()
                    } else {
                        selectedBooks = Set(deletedBooks.map { $0.persistentModelID })
                    }
                } label: {
                    Label(selectAllText, systemImage: selectedBooks.count == deletedBooks.count ? "circle" : "checkmark.circle")
                }.tint(.primary)
                Button(role: .destructive) {
                    guard !selectedBooks.isEmpty else { return }
                    deleteAction = .selectedBooks
                    showingDeleteConfirmation = true
                } label: { Label("Delete", systemImage: "trash") }.tint(.red)
            } else {
                Spacer()
                Button(role: .destructive) {
                    guard !deletedBooks.isEmpty else { return }
                    deleteAction = .emptyTrash
                    showingDeleteConfirmation = true
                } label: { Label("Empty Trash", systemImage: "trash") }.tint(.red)
            }
        }
    }

    private func performDelete() {
        switch deleteAction {
        case .emptyTrash: emptyTrash()
        case .singleBook(let book): permanentlyDelete(book)
        case .selectedBooks: permanentlyDeleteSelected()
        }
    }

    private func toggleSelection(for book: Book) { selectedBooks.toggle(book.persistentModelID) }

    private func restoreBook(_ book: Book) {
        book.deletedDate = nil
        modelContext.saveWithLogging("TrashView: Restored book")
    }

    private func restoreSelectedBooks() {
        for id in selectedBooks {
            if let book = deletedBooks.first(where: { $0.persistentModelID == id }) {
                book.deletedDate = nil
            }
        }
        modelContext.saveWithLogging("TrashView: Restored selected books")
        selectedBooks.removeAll()
        isSelecting = false
    }

    private func permanentlyDelete(_ book: Book) {
        modelContext.delete(book)
        modelContext.saveWithLogging("TrashView: Permanently deleted 1 book")
    }

    private func permanentlyDeleteSelected() {
        for id in selectedBooks {
            if let book = deletedBooks.first(where: { $0.persistentModelID == id }) {
                modelContext.delete(book)
            }
        }
        modelContext.saveWithLogging("TrashView: Permanently deleted \(selectedBooks.count) book(s)")
        selectedBooks.removeAll()
        isSelecting = false
    }

    private func emptyTrash() {
        for book in deletedBooks { modelContext.delete(book) }
        modelContext.saveWithLogging("TrashView: Emptied trash")
    }
}

#Preview {
    TrashView()
        .modelContainer(for: Book.self, inMemory: true)
}
