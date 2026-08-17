//
//  LocationPickerView.swift
//  Bookee
//
//  Location picker for selecting and managing locations on a book.
//

import SwiftUI
import SwiftData

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedLocations: Set<String>
    @AppStorage("locations") private var storedLocations: String = "[]"
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true

    @State private var newLocationName: String = ""
    @State private var showingAddAlert = false
    @State private var locationToEdit: String = ""
    @State private var editLocationName: String = ""
    @State private var showingEditAlert = false
    @State private var locations: [String] = []
    @State private var showingDeleteConfirmation = false
    @State private var locationToDelete: String? = nil

    var body: some View {
        Form {
            Section {
                ForEach(locations, id: \.self) { location in
                    Button {
                        if selectedLocations.contains(location) {
                            selectedLocations.remove(location)
                        } else {
                            selectedLocations.insert(location)
                        }
                    } label: {
                        HStack {
                            Text(location)
                            Spacer()
                            if selectedLocations.contains(location) {
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
                            locationToEdit = location
                            editLocationName = location
                            showingEditAlert = true
                        } label: { Image(systemName: "pencil") }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            locationToDelete = location
                            showingDeleteConfirmation = true
                        } label: { Label("Delete", systemImage: "trash") }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button {
                            locationToEdit = location
                            editLocationName = location
                            showingEditAlert = true
                        } label: { Label("Rename", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) {
                            locationToDelete = location
                            showingDeleteConfirmation = true
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onMove { from, to in
                    locations.move(fromOffsets: from, toOffset: to)
                    storedLocations = locations.asAppStorageString
                }

                if locations.isEmpty {
                    Text("No locations yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } footer: {
                if showFooters && !locations.isEmpty {
                    Text("Swipe right to rename a location, left to delete it.")
                }
            }
        }
        .onAppear {
            locations = storedLocations.asCategories
        }
        .onChange(of: storedLocations) { _, newValue in
            let updated = newValue.asCategories
            if updated != locations { locations = updated }
        }
        .navigationTitle("Locations")
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
                        newLocationName = ""
                        showingAddAlert = true
                    } label: { Label("Add Location", systemImage: "plus") }
                    .tint(.primary)
                }
            }
        }
        .locationManagementAlerts(
            newLocationName: $newLocationName,
            showingAddAlert: $showingAddAlert,
            onAdd: addLocation,
            editLocationName: $editLocationName,
            showingEditAlert: $showingEditAlert,
            onRename: { renameLocation(from: locationToEdit, to: editLocationName) },
            locationToDelete: $locationToDelete,
            showingDeleteConfirmation: $showingDeleteConfirmation,
            onDelete: { if let l = locationToDelete { deleteLocation(l) } }
        )
        .tint(.primary)
    }

    private func addLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty else { return }
        var list = storedLocations.asCategories
        if !list.contains(trimmed) {
            list.append(trimmed)
            storedLocations = list.asAppStorageString
        }
        selectedLocations.insert(trimmed)
        newLocationName = ""
    }

    private func renameLocation(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty, trimmed != old else { return }
        var list = storedLocations.asCategories
        if let index = list.firstIndex(of: old) {
            list[index] = trimmed
            storedLocations = list.asAppStorageString
        }
        if selectedLocations.contains(old) {
            selectedLocations.remove(old)
            selectedLocations.insert(trimmed)
        }
        updateBooksForRenamedLocation(from: old, to: trimmed, modelContext: modelContext)
    }

    private func deleteLocation(_ location: String) {
        var list = storedLocations.asCategories
        list.removeAll { $0 == location }
        storedLocations = list.asAppStorageString
        selectedLocations.remove(location)
        updateBooksForDeletedLocation(location, modelContext: modelContext)
    }
}
