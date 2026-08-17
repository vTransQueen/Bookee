//
//  ContentView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

/// Main library view — lists all books, enables add/edit/duplicate/delete and navigation to book detail.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Book> { $0.deletedDate == nil })
    private var rawNonDeletedBooks: [Book]

    private var allNonDeletedBooks: [Book] {
        rawNonDeletedBooks.filter { !$0.isUnsavedDuplicate }
    }

    @State private var isSelecting = false
    @State private var selectedBooks = Set<PersistentIdentifier>()
    @State private var selectedBookForEdit: Book?
    @State private var isEditingDuplicatedBook = false
    @State private var originalDuplicatedBookTitle: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var bookToDelete: Book?
    @State private var navigationStateManager = NavigationStateManager.shared
    @State private var isCurrentlyViewingSettings = false

    // Filter state
    @State private var filterStatus: ReadingStatus? = nil
    @State private var filterGenre: String? = nil
    @State private var filterRating: Int? = nil
    @State private var showingFilterSheet = false

    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .alphabetical
    @AppStorage("userName") private var userName: String = ""
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true

    private func persistContext() {
        modelContext.saveWithLogging("ContentView: Context saved")
    }

    // Sorted (but not filtered) list — used by CRUD actions that need the full set.
    private var sortedBooks: [Book] {
        switch sortOrder {
        case .alphabetical:
            return allNonDeletedBooks.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .authorAlphabetical:
            return allNonDeletedBooks.sorted {
                $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
        case .seriesAlphabetical:
            return allNonDeletedBooks.sorted { (a: Book, b: Book) -> Bool in
                let s0 = a.seriesName ?? ""
                let s1 = b.seriesName ?? ""
                if s0.isEmpty && s1.isEmpty { return false }
                if s0.isEmpty { return false }
                if s1.isEmpty { return true }
                return s0.localizedCaseInsensitiveCompare(s1) == .orderedAscending
            }
        case .genreAlphabetical:
            return allNonDeletedBooks.sorted {
                let g0 = $0.genres.first ?? ""
                let g1 = $1.genres.first ?? ""
                if g0.isEmpty && g1.isEmpty { return false }
                if g0.isEmpty { return false }
                if g1.isEmpty { return true }
                return g0.localizedCaseInsensitiveCompare(g1) == .orderedAscending
            }
        case .statusAlphabetical:
            return allNonDeletedBooks.sorted {
                $0.status.rawValue.localizedCaseInsensitiveCompare($1.status.rawValue) == .orderedAscending
            }
        case .rating:
            return allNonDeletedBooks.sorted {
                ($0.rating ?? -1) > ($1.rating ?? -1)
            }
        }
    }

    // Unique first-letters from the already-alphabetically-sorted filteredBooks, in order.
    private var alphabeticalSectionLetters: [String] {
        guard sortOrder == .alphabetical else { return [] }
        var seen = Set<String>()
        return filteredBooks.compactMap { book -> String? in
            guard let first = book.displayTitle.first else { return nil }
            let ch = String(first)
                .folding(options: .diacriticInsensitive, locale: .current)
                .uppercased()
            let letter = (ch.first?.isLetter == true) ? String(ch.first!) : "#"
            return seen.insert(letter).inserted ? letter : nil
        }
    }

    private func firstBook(forLetter letter: String) -> Book? {
        filteredBooks.first { book in
            guard let first = book.displayTitle.first else { return letter == "#" }
            let ch = String(first)
                .folding(options: .diacriticInsensitive, locale: .current)
                .uppercased()
            let bookLetter = (ch.first?.isLetter == true) ? String(ch.first!) : "#"
            return bookLetter == letter
        }
    }

    // Filtered list shown in the UI.
    private var filteredBooks: [Book] {
        var result = sortedBooks
        if let status = filterStatus  { result = result.filter { $0.status == status } }
        if let genre  = filterGenre   { result = result.filter { $0.genres.contains(genre) } }
        if let rating = filterRating  { result = result.filter { ($0.rating ?? 0) == rating } }
        return result
    }

    private var booksWithSeries: [Book] {
        filteredBooks.filter { !($0.seriesName ?? "").isEmpty }
    }

    private var booksWithoutSeries: [Book] {
        filteredBooks
            .filter { ($0.seriesName ?? "").isEmpty }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private var isFiltering: Bool {
        filterStatus != nil || filterGenre != nil || filterRating != nil
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 0..<12:  timeGreeting = "Good Morning"
        case 12..<17: timeGreeting = "Good Afternoon"
        case 17..<21: timeGreeting = "Good Evening"
        default:      timeGreeting = "Good Night"
        }
        let trimmedName = userName.trimmingCharacters(in: .whitespaces)
        return trimmedName.isEmpty ? timeGreeting : "\(timeGreeting), \(trimmedName)!"
    }

    var body: some View {
        NavigationStack(path: $navigationStateManager.navigationPath) {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        if sortOrder == .seriesAlphabetical {
                            if !booksWithSeries.isEmpty {
                                Section {
                                    ForEach(booksWithSeries) { book in
                                        bookRow(for: book)
                                    }
                                } header: {
                                    if isFiltering {
                                        Text("\(filteredBooks.count) of \(sortedBooks.count) book\(sortedBooks.count == 1 ? "" : "s")")
                                    } else {
                                        Text("Library")
                                    }
                                }
                            }
                            if !booksWithoutSeries.isEmpty {
                                Section("No Series Added") {
                                    ForEach(booksWithoutSeries) { book in
                                        bookRow(for: book)
                                    }
                                }
                            }
                        } else {
                            Section {
                                ForEach(filteredBooks) { book in
                                    bookRow(for: book)
                                }
                                .onMove(perform: nil)
                            } header: {
                                if !sortedBooks.isEmpty {
                                    if isFiltering {
                                        Text("\(filteredBooks.count) of \(sortedBooks.count) book\(sortedBooks.count == 1 ? "" : "s")")
                                    } else {
                                        Text("Library")
                                    }
                                }
                            } footer: {
                                if showFooters && !sortedBooks.isEmpty && !isFiltering {
                                    Text("Swipe right on a book to duplicate it, or left to delete it.")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)

                    if sortedBooks.isEmpty {
                        EmptyStatePlaceholder(
                            systemImage: "books.vertical",
                            title: "No Books Yet",
                            message: "Tap the + button to add your first book"
                        )
                    } else if filteredBooks.isEmpty {
                        EmptyStatePlaceholder(
                            systemImage: "line.3.horizontal.decrease.circle",
                            title: "No Matches",
                            message: "No books match the current filters"
                        )
                    }
                }
                .overlay(alignment: .trailing) {
                    if sortOrder == .alphabetical && !filteredBooks.isEmpty {
                        AlphabetScroller(letters: alphabeticalSectionLetters) { letter in
                            if let book = firstBook(forLetter: letter) {
                                proxy.scrollTo(book.persistentModelID, anchor: .top)
                            }
                        }
                        .padding(.trailing, 6)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: String.self) { destination in
                Group {
                    if destination == "Settings" {
                        SettingsView()
                            .onAppear {
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
            .sheet(isPresented: Binding(
                get: { selectedBookForEdit != nil },
                set: { if !$0 {
                    if let book = selectedBookForEdit, isEditingDuplicatedBook {
                        modelContext.delete(book)
                        persistContext()
                    }
                    selectedBookForEdit = nil
                    isEditingDuplicatedBook = false
                    originalDuplicatedBookTitle = ""
                }}
            )) {
                if let book = selectedBookForEdit {
                    NavigationStack {
                        AddEditBookView(
                            book: book,
                            shouldFocusOnTitle: isEditingDuplicatedBook,
                            isEditingDuplicatedBook: isEditingDuplicatedBook,
                            originalDuplicatedBookTitle: originalDuplicatedBookTitle,
                            onSave: {
                                if isEditingDuplicatedBook {
                                    book.isUnsavedDuplicate = false
                                    persistContext()
                                }
                                selectedBookForEdit = nil
                                isEditingDuplicatedBook = false
                                originalDuplicatedBookTitle = ""
                            },
                            onCancel: {
                                if isEditingDuplicatedBook {
                                    modelContext.delete(book)
                                    persistContext()
                                }
                                selectedBookForEdit = nil
                                isEditingDuplicatedBook = false
                                originalDuplicatedBookTitle = ""
                            }
                        )
                    }
                    .standardSheetPresentation()
                    .interactiveDismissDisabled(isEditingDuplicatedBook)
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterOptionsSheet(
                    filterStatus: $filterStatus,
                    filterGenre: $filterGenre,
                    filterRating: $filterRating
                )
            }
            .onChange(of: navigationStateManager.navigationPath) { oldPath, newPath in
                if !newPath.isEmpty && isSelecting {
                    isSelecting = false
                    selectedBooks.removeAll()
                }
                if newPath.count == 0 {
                    navigationStateManager.saveIsViewingSettings(false)
                    isCurrentlyViewingSettings = false
                } else if isCurrentlyViewingSettings && newPath.count < oldPath.count {
                    isCurrentlyViewingSettings = false
                    navigationStateManager.saveIsViewingSettings(false)
                }
            }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(appearanceMode.colorScheme)
            .background {
                AlertContainer {
                    Color.clear
                        .alert(bookToDelete != nil ? "Delete Book?" : "Delete Selected Books?",
                               isPresented: $showingDeleteConfirmation) {
                            Button("Cancel", role: .cancel) { bookToDelete = nil }
                            Button("Delete", role: .destructive) {
                                if let book = bookToDelete {
                                    deleteBook(book)
                                    bookToDelete = nil
                                } else {
                                    deleteSelectedBooks()
                                }
                            }
                        } message: {
                            if let book = bookToDelete {
                                Text("This will move '\(book.displayTitle)' to the trash. You can restore it within 30 days.")
                            } else {
                                let count = selectedBooks.count
                                Text("This will move \(count) book\(count == 1 ? "" : "s") to the trash. You can restore them within 30 days.")
                            }
                        }
                }
            }
            .onAppear {}
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func bookRow(for book: Book) -> some View {
        BookRowView(
            book: book,
            isSelecting: isSelecting,
            isSelected: selectedBooks.contains(book.persistentModelID),
            dateFormat: dateFormat,
            highlightColor: highlightColor,
            onToggleSelection: { selectedBooks.toggle(book.persistentModelID) },
            onEdit: { selectedBookForEdit = book },
            onDuplicate: { duplicateBook(book) },
            onDelete: { bookToDelete = book; showingDeleteConfirmation = true }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var leadingToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink(value: "Settings") {
                Label("Settings", systemImage: "gear")
            }
            .tint(.primary)
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
                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .disabled(sortedBooks.isEmpty)
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }
                .tint(.primary)
            }
        }
    }

    @ToolbarContentBuilder
    private var bottomToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if isSelecting {
                Spacer()
                let allSelected = selectedBooks.count == filteredBooks.count
                Button {
                    if allSelected { selectedBooks.removeAll() }
                    else { selectedBooks = Set(filteredBooks.map { $0.persistentModelID }) }
                } label: {
                    Label(allSelected ? "Deselect All" : "Select All",
                          systemImage: allSelected ? "circle" : "checkmark.circle")
                }.tint(.primary)
                Button(role: .destructive) {
                    if !selectedBooks.isEmpty { showingDeleteConfirmation = true }
                } label: { Label("Delete", systemImage: "trash") }.tint(.red)
            } else {
                Button { showingFilterSheet = true } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }.tint(isFiltering ? highlightColor : .primary)

                Spacer()

                Button { createNewBook() } label: {
                    Label("Add Book", systemImage: "plus")
                }.tint(.primary)
            }
        }
    }

    // MARK: - Actions


    private func deleteSelectedBooks() {
        for id in selectedBooks {
            if let book = sortedBooks.first(where: { $0.persistentModelID == id }) {
                book.deletedDate = Date()
            }
        }
        persistContext()
        selectedBooks.removeAll()
        isSelecting = false
    }

    private func deleteBook(_ book: Book) {
        book.deletedDate = Date()
        persistContext()
    }

    private func duplicateBook(_ book: Book) {
        let minSortOrder = (sortedBooks.min(by: { $0.manualSortOrder < $1.manualSortOrder })?.manualSortOrder ?? 0) - 1
        let dup = Book(
            timestamp: Date(),
            title: book.title,
            author: book.author,
            manualSortOrder: minSortOrder,
            status: book.status
        )
        dup.rating = book.rating
        dup.pageCount = book.pageCount
        dup.currentPage = nil
        dup.dateStarted = nil
        dup.dateFinished = nil
        dup.genresData = book.genresData
        dup.notes = book.notes
        dup.coverImageData = book.coverImageData
        dup.isUnsavedDuplicate = true
        modelContext.insert(dup)
        isEditingDuplicatedBook = true
        originalDuplicatedBookTitle = book.displayTitle
        selectedBookForEdit = dup
    }

    private func createNewBook() {
        let minSortOrder = (sortedBooks.min(by: { $0.manualSortOrder < $1.manualSortOrder })?.manualSortOrder ?? 0) - 1
        let newBook = Book(timestamp: Date(), title: "", author: "", manualSortOrder: minSortOrder)
        newBook.isUnsavedDuplicate = true
        modelContext.insert(newBook)
        isEditingDuplicatedBook = true
        originalDuplicatedBookTitle = ""
        selectedBookForEdit = newBook
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
