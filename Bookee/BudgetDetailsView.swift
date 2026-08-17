//
//  AddEditBookView.swift
//  Bookee
//
//  Form for creating or editing a book. Presents as a sheet with staged local state.
//

import SwiftUI
import SwiftData
import PhotosUI

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
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var status: ReadingStatus = .toRead
    @State private var rating: Int = 0
    @State private var selectedGenres: Set<String> = []
    @State private var selectedLocations: Set<String> = []
    @State private var notes: String = ""
    @State private var coverImageItem: PhotosPickerItem? = nil
    @State private var coverImageData: Data? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingGenrePicker = false
    @State private var showingLocationPicker = false
    @State private var ownership: BookOwnership? = nil
    @State private var bookFormat: BookFormat? = nil
    @State private var seriesName: String = ""
    @State private var seriesNumber: String = ""

    private enum Field: Hashable { case title, author, seriesName, seriesNumber }
    @FocusState private var focusedField: Field?

    var isDoneButtonDisabled: Bool {
        isEditingDuplicatedBook && !originalDuplicatedBookTitle.isEmpty && title == originalDuplicatedBookTitle
    }

    var body: some View {
        Form {
            titleSection
            detailsSection
            notesSection
            coverSection
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: coverImageItem) { _, newItem in
            Task {
                if let item = newItem,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    coverImageData = data
                }
            }
        }
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
                Spacer()
                PhotosPicker(selection: $coverImageItem, matching: .images) {
                    Label("Cover Photo", systemImage: "photo")
                }
                .tint(.primary)
            }
        }
        .onAppear {
            initializeValues()
            if shouldFocusOnTitle { focusedField = .title }
        }
        .navigationDestination(isPresented: $showingGenrePicker) {
            CategoryPickerView(selectedGenres: $selectedGenres)
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
                    focusedField = .seriesNumber
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
                CursorAtEndTextField_SwiftUI(text: $seriesNumber, placeholder: "Number") {
                    focusedField = .author
                }
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .returnKey(.next)
                .focused($focusedField, equals: .seriesNumber)
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .seriesNumber }

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
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
            } label: {
                Text("Status")
            }

            Picker(selection: $bookFormat) {
                ForEach(BookFormat.allCases, id: \.self) { f in
                    Label(f.rawValue, systemImage: f.icon).tag(BookFormat?.some(f))
                }
                Divider()
                Label("Not Set", systemImage: "xmark").tag(BookFormat?.none)
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
                    Label(o.rawValue, systemImage: o.icon).tag(BookOwnership?.some(o))
                }
                Divider()
                Label("Not Set", systemImage: "xmark").tag(BookOwnership?.none)
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

    private var coverSection: some View {
        Section {
            if coverImageData == nil {
                Text("Tap \(Image(systemName: "photo")) in the toolbar to add a cover photo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let data = coverImageData, let uiImage = UIImage(data: data) {
                HStack {
                    Spacer()
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                .listRowBackground(Color.clear)

                Button(role: .destructive) {
                    coverImageData = nil
                    coverImageItem = nil
                } label: {
                    Label("Remove Cover", systemImage: "trash")
                }
            }

        } header: {
            Text("Cover")
        }
    }

    // MARK: - Logic

    private func initializeValues() {
        title = book.title
        author = book.author
        status = book.status
        rating = book.rating ?? 0
        selectedGenres = Set(book.genres)
        selectedLocations = Set(book.locations)
        notes = book.notes ?? ""
        coverImageData = book.coverImageData
        ownership = book.ownership
        bookFormat = book.bookFormat
        seriesName = book.seriesName ?? ""
        seriesNumber = book.seriesNumber.map { String($0) } ?? ""
    }

    private func saveChanges() {
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.status = status
        book.rating = rating > 0 ? rating : nil
        book.genres = Array(selectedGenres).sorted()
        book.locations = Array(selectedLocations).sorted()
        book.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        book.coverImageData = coverImageData
        book.ownership = ownership
        book.bookFormat = bookFormat
        book.seriesName = seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : seriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        book.seriesNumber = Int(seriesNumber.trimmingCharacters(in: .whitespacesAndNewlines))
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
