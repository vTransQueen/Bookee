//
//  ViewExtensions.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

// MARK: - View Extensions

extension View {
    /// Conditionally applies a transformation to a view based on a boolean condition.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }

    /// Monitors a boolean FocusState binding and trims whitespace from the text when focus is lost.
    func trimWhitespaceOnEditingEnd(_ text: Binding<String>, isFocused: FocusState<Bool>.Binding) -> some View {
        self.onChange(of: isFocused.wrappedValue) { _, newValue in
            if !newValue {
                text.wrappedValue = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

// MARK: - Standard Sheet Presentation

extension View {
    func standardSheetPresentation() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(40)
            .presentationBackground(.thinMaterial)
    }
}

// MARK: - Notification Name Constants

extension Notification.Name {
    static let genreRenamed = Notification.Name("GenreRenamed")
}

// MARK: - Genre Management Alerts

extension View {
    /// Attaches the three standard genre management alerts (New / Rename / Delete).
    func genreManagementAlerts(
        newGenreName: Binding<String>,
        showingAddAlert: Binding<Bool>,
        onAdd: @escaping () -> Void,
        editGenreName: Binding<String>,
        showingEditAlert: Binding<Bool>,
        onRename: @escaping () -> Void,
        genreToDelete: Binding<String?>,
        showingDeleteConfirmation: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) -> some View {
        self
            .alert("New Genre", isPresented: showingAddAlert) {
                TextField("Genre Name", text: newGenreName)
                    .textInputAutocapitalization(.words)
                Button("Add") { onAdd() }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Rename Genre", isPresented: showingEditAlert) {
                TextField("Genre Name", text: editGenreName)
                    .textInputAutocapitalization(.words)
                Button("Save") { onRename() }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Delete Genre?", isPresented: showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if genreToDelete.wrappedValue != nil { onDelete() }
                    genreToDelete.wrappedValue = nil
                }
                Button("Cancel", role: .cancel) { genreToDelete.wrappedValue = nil }
            }
    }
}

// MARK: - Location Management Alerts

extension View {
    func locationManagementAlerts(
        newLocationName: Binding<String>,
        showingAddAlert: Binding<Bool>,
        onAdd: @escaping () -> Void,
        editLocationName: Binding<String>,
        showingEditAlert: Binding<Bool>,
        onRename: @escaping () -> Void,
        locationToDelete: Binding<String?>,
        showingDeleteConfirmation: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) -> some View {
        self
            .alert("New Location", isPresented: showingAddAlert) {
                TextField("Location Name", text: newLocationName)
                    .textInputAutocapitalization(.words)
                Button("Add") { onAdd() }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Rename Location", isPresented: showingEditAlert) {
                TextField("Location Name", text: editLocationName)
                    .textInputAutocapitalization(.words)
                Button("Save") { onRename() }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Delete Location?", isPresented: showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if locationToDelete.wrappedValue != nil { onDelete() }
                    locationToDelete.wrappedValue = nil
                }
                Button("Cancel", role: .cancel) { locationToDelete.wrappedValue = nil }
            }
    }
}
