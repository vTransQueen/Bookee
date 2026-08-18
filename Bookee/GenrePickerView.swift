//
//  GenrePickerView.swift
//  Bookee
//
//  Genre picker for selecting and managing genres on a book.
//

import SwiftUI
import SwiftData

// MARK: - Genre Picker View

struct GenrePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedGenres: Set<String>
    @AppStorage("genres") private var storedGenres: String = "[]"
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true

    @State private var newGenreName: String = ""
    @State private var showingAddAlert = false
    @State private var genreToEdit: String = ""
    @State private var editGenreName: String = ""
    @State private var showingEditAlert = false
    @State private var genres: [String] = []
    @State private var showingDeleteConfirmation = false
    @State private var genreToDelete: String? = nil

    var body: some View {
        Form {
            Section {
                ForEach(genres, id: \.self) { genre in
                    Button {
                        if selectedGenres.contains(genre) {
                            selectedGenres.remove(genre)
                        } else {
                            selectedGenres.insert(genre)
                        }
                    } label: {
                        HStack {
                            Text(genre)
                            Spacer()
                            if selectedGenres.contains(genre) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(highlightColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .leading) {
                        Button {
                            genreToEdit = genre
                            editGenreName = genre
                            showingEditAlert = true
                        } label: { Image(systemName: "pencil") }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            genreToDelete = genre
                            showingDeleteConfirmation = true
                        } label: { Label("Delete", systemImage: "trash") }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button {
                            genreToEdit = genre
                            editGenreName = genre
                            showingEditAlert = true
                        } label: { Label("Rename", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) {
                            genreToDelete = genre
                            showingDeleteConfirmation = true
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onMove { from, to in
                    genres.move(fromOffsets: from, toOffset: to)
                    storedGenres = genres.asAppStorageString
                }

                if genres.isEmpty {
                    Text("No genres yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } footer: {
                if showFooters && !genres.isEmpty {
                    Text("Swipe right to rename a genre, left to delete it.")
                }
            }
        }
        .onAppear {
            genres = storedGenres.asStringList
        }
        .onChange(of: storedGenres) { _, newValue in
            let updated = newValue.asStringList
            if updated != genres { genres = updated }
        }
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .tint(.primary)
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Spacer()
                    Button {
                        newGenreName = ""
                        showingAddAlert = true
                    } label: { Label("Add Genre", systemImage: "plus") }
                    .tint(.primary)
                }
            }
        }
        .genreManagementAlerts(
            newGenreName: $newGenreName,
            showingAddAlert: $showingAddAlert,
            onAdd: addGenre,
            editGenreName: $editGenreName,
            showingEditAlert: $showingEditAlert,
            onRename: { renameGenre(from: genreToEdit, to: editGenreName) },
            genreToDelete: $genreToDelete,
            showingDeleteConfirmation: $showingDeleteConfirmation,
            onDelete: { if let g = genreToDelete { deleteGenre(g) } }
        )
        .tint(.primary)
    }

    private func addGenre() {
        let trimmed = newGenreName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty else { return }
        var list = storedGenres.asStringList
        if !list.contains(trimmed) {
            list.append(trimmed)
            storedGenres = list.asAppStorageString
        }
        selectedGenres.insert(trimmed)
        newGenreName = ""
    }

    private func renameGenre(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty, trimmed != old else { return }
        var list = storedGenres.asStringList
        if let index = list.firstIndex(of: old) {
            list[index] = trimmed
            storedGenres = list.asAppStorageString
        }
        if selectedGenres.contains(old) {
            selectedGenres.remove(old)
            selectedGenres.insert(trimmed)
        }
        updateBooksForRenamedGenre(from: old, to: trimmed, modelContext: modelContext)
        NotificationCenter.default.post(
            name: .genreRenamed,
            object: nil,
            userInfo: ["oldName": old, "newName": trimmed]
        )
    }

    private func deleteGenre(_ genre: String) {
        var list = storedGenres.asStringList
        list.removeAll { $0 == genre }
        storedGenres = list.asAppStorageString
        selectedGenres.remove(genre)
        updateBooksForDeletedGenre(genre, modelContext: modelContext)
    }
}
