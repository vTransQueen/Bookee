//
//  ViewExtensions.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Cancel Toolbar Item

/// Reusable toolbar "Cancel" button used by Add/Edit views.
struct CancelToolbarItem: ToolbarContent {
    let dismiss: DismissAction
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Label("Cancel", systemImage: "xmark") }
                .tint(.primary)
        }
    }
}

// MARK: - Keyboard Utilities

/// Programmatically dismisses the UIKit keyboard.
func resignKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

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

// MARK: - Genre Renamed Observer

extension View {
    /// Listens for GenreRenamed notifications and updates a book's genres array in-place.
    func onGenreRenamed(genres: Binding<[String]>) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .genreRenamed)) { notification in
            guard let userInfo = notification.userInfo,
                  let oldName = userInfo["oldName"] as? String,
                  let newName = userInfo["newName"] as? String else { return }
            genres.wrappedValue = genres.wrappedValue.map { $0 == oldName ? newName : $0 }
        }
    }
}

// MARK: - Notification Name Constants

extension Notification.Name {
    static let genreRenamed   = Notification.Name("GenreRenamed")
    static let highlightNewItem = Notification.Name("HighlightNewItem")
}

// MARK: - Destructive Delete Alert

extension View {
    func destructiveDeleteAlert(
        title: String = "Delete?",
        message: String? = nil,
        isPresented: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert(title, isPresented: isPresented) {
                        Button("Delete", role: .destructive, action: onDelete)
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        if let msg = message { Text(msg) }
                    }
            }
        }
    }
}

// MARK: - Rename Attachment Alert

extension View {
    func renameAttachmentAlert(
        isPresented: Binding<Bool>,
        renameText: Binding<String>,
        onSave: @escaping (String) -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert("Rename Attachment", isPresented: isPresented) {
                        TextField("File Name", text: renameText)
                            .textInputAutocapitalization(.words)
                        Button("Save") {
                            let trimmed = renameText.wrappedValue.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            onSave(trimmed)
                        }
                        Button("Cancel", role: .cancel) { isPresented.wrappedValue = false }
                    }
            }
        }
    }
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
        self.background {
            AlertContainer {
                Color.clear
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
    }
}

// MARK: - Safe Binding Helper

/// Utility for creating stable, identity-based bindings to elements within arrays.
struct SafeBindingHelper {
    static func binding<T: Identifiable>(for item: T, in array: Binding<[T]>) -> Binding<T>? where T.ID: Equatable {
        guard let index = array.wrappedValue.firstIndex(where: { $0.id == item.id }) else { return nil }
        return Binding(
            get: { array.wrappedValue[index] },
            set: { newValue in
                if let currentIndex = array.wrappedValue.firstIndex(where: { $0.id == item.id }) {
                    array.wrappedValue[currentIndex] = newValue
                }
            }
        )
    }
}
