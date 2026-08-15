//
//  ViewExtensions.swift
//  K Test
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Budget Data Change Modifier

/// Attaches the four identical `onChange(of:)` guard-and-persist handlers shared by
/// BudgetVisualizerPageView and MonthDetailsPageView.
extension View {
    func onBudgetDataChange(
        expenses: [Expense],
        incomes: [Income],
        attachments: [BudgetAttachment],
        reallocations: [Reallocation],
        isInitialLoad: Bool,
        persist: @escaping () -> Void
    ) -> some View {
        self
            .onChange(of: expenses)      { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: incomes)       { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: attachments)   { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: reallocations) { _, _ in if !isInitialLoad { persist() } }
    }
}

// MARK: - Cancel Toolbar Item

/// Reusable toolbar "Cancel" button used by all Add/Edit and Reallocation views.
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
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Monitors a boolean FocusState binding and trims whitespace from the text when focus is lost.
    func trimWhitespaceOnEditingEnd(_ text: Binding<String>, isFocused: FocusState<Bool>.Binding) -> some View {
        self.onChange(of: isFocused.wrappedValue) { _, newValue in
            if !newValue {
                text.wrappedValue = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Attaches the "Edit Recurring Item" scope-selection alert as a background overlay.
    /// Shared by EditExpenseView and EditIncomeView to avoid duplicating the identical alert block.
    func recurringEditAlert(
        isPresented: Binding<Bool>,
        pendingScope: Binding<RecurringScope?>,
        applyEdit: @escaping () -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert("Edit Recurring Item", isPresented: isPresented) {
                        Button("All Occurrences", role: .destructive) {
                            pendingScope.wrappedValue = .all
                            applyEdit()
                        }
                        Button("Current and Future", role: .destructive) {
                            pendingScope.wrappedValue = .currentAndFuture
                            applyEdit()
                        }
                        Button("Current Occurrence", role: .destructive) {
                            pendingScope.wrappedValue = .currentOnly
                            applyEdit()
                        }
                        Button("Cancel", role: .cancel) {
                            pendingScope.wrappedValue = nil
                        }
                    } message: {
                        Text("This is a recurring item. Choose which occurrences to update:")
                    }
            }
        }
    }
}

// MARK: - Standard Sheet Presentation

extension View {
    /// Applies the standard full-screen sheet presentation style used throughout the app.
    func standardSheetPresentation() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(40)
            .presentationBackground(.thinMaterial)
    }
}

// MARK: - Category Renamed Observer

extension View {
    /// Listens for CategoryRenamed notifications and updates both arrays in-place.
    func onCategoryRenamed(expenses: Binding<[Expense]>, incomes: Binding<[Income]>) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .categoryRenamed)) { notification in
            guard let userInfo = notification.userInfo,
                  let oldName = userInfo["oldName"] as? String,
                  let newName = userInfo["newName"] as? String else { return }
            expenses.wrappedValue = renamingCategory(oldName, to: newName, in: expenses.wrappedValue)
            incomes.wrappedValue  = renamingCategory(oldName, to: newName, in: incomes.wrappedValue)
        }
    }
}

// MARK: - Notification Name Constants

extension Notification.Name {
    static let categoryRenamed            = Notification.Name("CategoryRenamed")
    static let highlightNewItem           = Notification.Name("HighlightNewItem")
    static let highlightBudgetOverviewRow = Notification.Name("HighlightBudgetOverviewRow")
}

// MARK: - Destructive Delete Alert

extension View {
    /// Attaches a destructive "Delete" confirmation alert using the AlertContainer pattern.
    /// The alert title and optional message are configurable; buttons are always Delete (destructive) + Cancel.
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
                        if let msg = message {
                            Text(msg)
                        }
                    }
            }
        }
    }
}

// MARK: - Rename Attachment Alert

extension View {
    /// Attaches the standard "Rename Attachment" alert with text field and extension-aware save.
    /// Shared by AttachmentManagementView and BudgetAttachmentManagementView.
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

// MARK: - Category Management Alerts

extension View {
    /// Attaches the three standard category management alerts (New / Rename / Delete)
    /// as a single modifier. Shared by CategoryPickerView and FilterOptionsSheet.
    func categoryManagementAlerts(
        newCategoryName: Binding<String>,
        showingAddAlert: Binding<Bool>,
        onAdd: @escaping () -> Void,
        editCategoryName: Binding<String>,
        showingEditAlert: Binding<Bool>,
        onRename: @escaping () -> Void,
        categoryToDelete: Binding<String?>,
        showingDeleteConfirmation: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) -> some View {
        self
            .background {
                AlertContainer {
                    Color.clear
                        .alert("New Category", isPresented: showingAddAlert) {
                            TextField("Category Name", text: newCategoryName)
                                .textInputAutocapitalization(.words)
                            Button("Add") { onAdd() }
                            Button("Cancel", role: .cancel) { }
                        }
                        .alert("Rename Category", isPresented: showingEditAlert) {
                            TextField("Category Name", text: editCategoryName)
                                .textInputAutocapitalization(.words)
                            Button("Save") { onRename() }
                            Button("Cancel", role: .cancel) { }
                        }
                        .alert("Delete Category?", isPresented: showingDeleteConfirmation) {
                            Button("Delete", role: .destructive) {
                                if categoryToDelete.wrappedValue != nil { onDelete() }
                                categoryToDelete.wrappedValue = nil
                            }
                            Button("Cancel", role: .cancel) { categoryToDelete.wrappedValue = nil }
                        }
                }
            }
    }
}

// MARK: - Safe Binding Helper

/// Utility for creating stable, identity-based bindings to elements within arrays.
/// Useful for passing bindings to SwiftUI views without risking index-based crashes.
struct SafeBindingHelper {
    /// Creates a binding to a specific array element using its identity rather than its index.
    ///
    /// - Parameters:
    ///   - item: The identifiable item to create a binding for (used to match by ID)
    ///   - array: A binding to the array containing the item
    /// - Returns: A binding to the item if it exists in the array, or `nil` if not found
    ///
    /// - Note: The getter captures the initial index but doesn't re-validate it on access,
    ///         which could be unsafe if the array is mutated between binding creation and use.
    ///         The setter safely re-validates the item's position before updating.
    static func binding<T: Identifiable>(for item: T, in array: Binding<[T]>) -> Binding<T>? where T.ID: Equatable {
        guard let index = array.wrappedValue.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }
        return Binding(
            // WARNING: The getter uses the captured index without re-validating.
            get: { array.wrappedValue[index] },
            set: { newValue in
                if let currentIndex = array.wrappedValue.firstIndex(where: { $0.id == item.id }) {
                    array.wrappedValue[currentIndex] = newValue
                }
            }
        )
    }
}
