//
//  AddEditBookView.swift
//  Bookee
//
//  Form for creating or editing a book. Presents as a sheet with staged local state.
//

import SwiftUI
import SwiftData

struct AddEditBookView: View {
    @Bindable var book: Book
    var shouldFocusOnTitle: Bool = false
    var isEditingDuplicatedBook: Bool = false
    var originalDuplicatedBookTitle: String = ""
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("showFooters") private var showFooters: Bool = true
    @HighlightColorStorage private var highlightColor

    // Staged local state
    @State private var title: String
    @State private var author: String
    @State private var status: ReadingStatus
    @State private var rating: Int
    @State private var selectedGenres: Set<String>
    @State private var selectedLocations: Set<String>
    @State private var notes: String
    @State private var showingDeleteConfirmation = false
    @State private var showingGenrePicker = false
    @State private var showingLocationPicker = false
    @State private var ownership: BookOwnership?
    @State private var bookFormat: BookFormat?
    @State private var seriesName: String
    @State private var seriesNumber: Int
    @State private var seriesTotalCount: Int

    init(book: Book, shouldFocusOnTitle: Bool = false, isEditingDuplicatedBook: Bool = false, originalDuplicatedBookTitle: String = "", onSave: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.book = book
        self.shouldFocusOnTitle = shouldFocusOnTitle
        self.isEditingDuplicatedBook = isEditingDuplicatedBook
        self.originalDuplicatedBookTitle = originalDuplicatedBookTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _status = State(initialValue: book.status)
        _rating = State(initialValue: book.rating ?? 0)
        _selectedGenres = State(initialValue: Set(book.genres))
        _selectedLocations = State(initialValue: Set(book.locations))
        _notes = State(initialValue: book.notes ?? "")
        _ownership = State(initialValue: book.ownership ?? .unowned)
        _bookFormat = State(initialValue: book.bookFormat ?? .paperback)
        _seriesName = State(initialValue: book.seriesName ?? "")
        _seriesNumber = State(initialValue: book.seriesNumber ?? 1)
        _seriesTotalCount = State(initialValue: book.seriesTotalCount ?? 1)
    }

    private enum Field: Hashable { case title, author, seriesName }
    @FocusState private var focusedField: Field?

    var isDoneButtonDisabled: Bool {
        isEditingDuplicatedBook && !originalDuplicatedBookTitle.isEmpty && title == originalDuplicatedBookTitle
    }

    var body: some View {
        Form {
            titleSection
            detailsSection
            notesSection
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Edit Book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { revertChanges() } label: { Label("Cancel", systemImage: "xmark") }
                    .tint(.primary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { saveChanges() } label: { Label("Done", systemImage: "checkmark") }
                    .tint(.primary)
                    .disabled(isDoneButtonDisabled)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if !isEditingDuplicatedBook {
                    Button { showingDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
                        .tint(.red)
                }
            }
        }
        .onAppear {
            if shouldFocusOnTitle { focusedField = .title }
        }
        .navigationDestination(isPresented: $showingGenrePicker) {
            GenrePickerView(selectedGenres: $selectedGenres)
        }
        .navigationDestination(isPresented: $showingLocationPicker) {
            LocationPickerView(selectedLocations: $selectedLocations)
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert("Move to Trash?", isPresented: $showingDeleteConfirmation) {
                        Button("Delete", role: .destructive) { performDelete() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will move '\(title.isEmpty ? "this book" : title)' to the trash. You can restore it within 30 days.")
                    }
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            HStack {
                Text("Title")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $title, placeholder: "Book") {
                    focusedField = .seriesName
                }
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .returnKey(.next)
                .focused($focusedField, equals: .title)
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .title }

            HStack {
                Text("Series")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $seriesName, placeholder: "Name") {
                    focusedField = .author
                }
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .returnKey(.next)
                .focused($focusedField, equals: .seriesName)
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .seriesName }

            HStack {
                Text("Book #")
                Spacer()
                Menu {
                    ForEach(1...99, id: \.self) { num in
                        Button("\(num)") { seriesNumber = num }
                    }
                } label: {
                    Text("\(seriesNumber)")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Text("/")
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(1...99, id: \.self) { num in
                        Button("\(num)") { seriesTotalCount = num }
                    }
                } label: {
                    Text("\(seriesTotalCount)")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Author")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $author, placeholder: "Name") {
                    focusedField = nil
                }
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .returnKey(.next)
                .focused($focusedField, equals: .author)
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .author }

            Button {
                showingGenrePicker = true
            } label: {
                HStack {
                    Text("Genres")
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedGenres.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(selectedGenres.sorted().joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .tint(.primary)
        } header: {
            Text("Book Details")
        }
    }

    private var detailsSection: some View {
        Section {
            Picker(selection: $status) {
                ForEach(ReadingStatus.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            } label: {
                Text("Status")
            }

            Picker(selection: $bookFormat) {
                ForEach(BookFormat.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(BookFormat?.some(f))
                }
            } label: {
                Text("Format")
            }

            Button {
                showingLocationPicker = true
            } label: {
                HStack {
                    Text("Location")
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedLocations.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(selectedLocations.sorted().joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .tint(.primary)

            Picker(selection: $ownership) {
                ForEach(BookOwnership.allCases, id: \.self) { o in
                    Text(o.rawValue).tag(BookOwnership?.some(o))
                }
            } label: {
                Text("Ownership")
            }

            HStack {
                Text("Rating")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .foregroundStyle(star <= rating ? highlightColor : .secondary)
                            .onTapGesture {
                                rating = star == rating ? 0 : star
                            }
                    }
                }
            }
        } header: {
            Text("Status & Rating")
        }
    }

    private var notesSection: some View {
        Section {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
        } header: {
            Text("Notes")
        }
    }

    // MARK: - Logic

    private func saveChanges() {
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.status = status
        book.rating = rating > 0 ? rating : nil
        book.genres = Array(selectedGenres).sorted()
        book.locations = Array(selectedLocations).sorted()
        book.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        book.ownership = ownership
        book.bookFormat = bookFormat
        book.seriesName = seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : seriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        book.seriesNumber = seriesNumber
        book.seriesTotalCount = seriesTotalCount
        book.lastModifiedDate = Date()
        modelContext.saveWithLogging("AddEditBookView: saved book '\(book.title)'")
        onSave?()
    }

    private func revertChanges() {
        onCancel?()
    }

    private func performDelete() {
        book.deletedDate = Date()
        modelContext.saveWithLogging("AddEditBookView: moved book to trash")
        onCancel?()
        dismiss()
    }
}
