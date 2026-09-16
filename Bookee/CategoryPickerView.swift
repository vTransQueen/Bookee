//
//  CategoryPickerView.swift
//  Bookee
//
//  Modal picker for selecting or creating transaction categories.
//

import SwiftUI
import SwiftData

// MARK: - Hidden Categories Page

struct HiddenCategoriesPage: View {
    @Binding var localHiddenCategories: [String]
    @Bindable var item: Item
    let month: Int
    let year: Int
    @AppStorage("transactionCategories") private var storedCategories: String = "[]"
    @HighlightColorStorage private var highlightColor

    private var hiddenInThisBudget: [String] {
        let all = Set(storedCategories.asCategories)
        return localHiddenCategories.filter { all.contains($0) }
    }

    private var categoryCounts: [String: Int] { buildCategoryCounts(for: item, month: month, year: year) }

    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(hiddenInThisBudget, id: \.self) { category in
                        HStack {
                            Text(category)
                            Text("\(categoryCounts[category, default: 0])")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                unhideCategory(category)
                            } label: {
                                Image(systemName: "eye")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                unhideCategory(category)
                            } label: {
                                Label("Unhide", systemImage: "eye")
                            }
                            .tint(.primary)
                        }
                    }
                }
            }

            if hiddenInThisBudget.isEmpty {
                EmptyStatePlaceholder(
                    systemImage: "eye.slash",
                    title: "No Hidden Categories",
                    message: "Categories you hide will appear here."
                )
            }
        }
        .navigationTitle("Hidden")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
    }

    private func unhideCategory(_ category: String) {
        localHiddenCategories.removeAll { $0 == category }
        item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        try? item.modelContext?.save()
    }
}

// MARK: - Category Picker View

struct CategoryPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedCategories: Set<String>
    @Bindable var item: Item
    let month: Int
    let year: Int
    @AppStorage("transactionCategories") private var storedCategories: String = "[]"
    @HighlightColorStorage private var highlightColor
    @State private var newCategoryName: String = ""
    @State private var showingAddAlert = false
    @State private var categoryToEdit: String = ""
    @State private var editCategoryName: String = ""
    @State private var showingEditAlert = false
    @State private var categories: [String] = []
    @State private var localHiddenCategories: [String] = []
    @State private var showingHiddenCategories = false
    @State private var showingDeleteConfirmation = false
    @State private var categoryToDelete: String? = nil
    private let protectedCategories: Set<String> = ["Reimbursed", "Reimbursement", "Pending Reimbursement"]

    private var visibleCategories: [String] {
        categories.filter { !localHiddenCategories.contains($0) }
    }

    private var categoryCounts: [String: Int] { buildCategoryCounts(for: item, month: month, year: year) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("All")
                    Text("\(categoryCounts.values.reduce(0, +))")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)

                ForEach(visibleCategories, id: \.self) { category in
                    categoryRow(for: category)
                }
                .onMove { from, to in
                    var visible = visibleCategories
                    visible.move(fromOffsets: from, toOffset: to)
                    let hiddenSet = Set(localHiddenCategories)
                    var result: [String] = []
                    var visIdx = 0
                    for cat in categories {
                        if hiddenSet.contains(cat) {
                            result.append(cat)
                        } else {
                            result.append(visible[visIdx])
                            visIdx += 1
                        }
                    }
                    categories = result
                    storedCategories = categories.asAppStorageString
                }

                Button {
                    selectedCategories = [SettingsDefault.uncategorizedSentinel]
                } label: {
                    HStack {
                        Text("Uncategorized")
                        Text("\(categoryCounts[SettingsDefault.uncategorizedSentinel, default: 0])")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        if selectedCategories == [SettingsDefault.uncategorizedSentinel] {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(highlightColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            Section {
                Button {
                    showingHiddenCategories = true
                } label: {
                    HStack {
                        Text("Hidden Categories")
                        Text("\(localHiddenCategories.filter { categories.contains($0) }.count)")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .navigationDestination(isPresented: $showingHiddenCategories) {
            HiddenCategoriesPage(localHiddenCategories: $localHiddenCategories, item: item, month: month, year: year)
        }
        .onAppear {
            categories = storedCategories.asCategories
            localHiddenCategories = item.hiddenFilterCategories?.asCategories ?? []
        }
        .onChange(of: storedCategories) { _, newValue in
            let updated = newValue.asCategories
            if updated != categories {
                categories = updated
            }
        }
        .onChange(of: item.hiddenFilterCategories) { _, newValue in
            localHiddenCategories = newValue?.asCategories ?? []
            modelContext.saveWithLogging("category picker")
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    selectedCategories = [SettingsDefault.uncategorizedSentinel]
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .tint(.primary)
                .disabled(selectedCategories == [SettingsDefault.uncategorizedSentinel])
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    newCategoryName = ""
                    showingAddAlert = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .tint(.primary)
            }
        }
        .categoryManagementAlerts(
            newCategoryName: $newCategoryName,
            showingAddAlert: $showingAddAlert,
            onAdd: addCategory,
            editCategoryName: $editCategoryName,
            showingEditAlert: $showingEditAlert,
            onRename: { renameCategory(from: categoryToEdit, to: editCategoryName) },
            categoryToDelete: $categoryToDelete,
            showingDeleteConfirmation: $showingDeleteConfirmation,
            onDelete: { if let cat = categoryToDelete { deleteCategory(cat) } }
        )
        .tint(.primary)
    }

    @ViewBuilder
    private func categoryRow(for category: String) -> some View {
        Button {
            selectedCategories.remove(SettingsDefault.uncategorizedSentinel)
            if selectedCategories.contains(category) {
                selectedCategories.remove(category)
                if selectedCategories.isEmpty {
                    selectedCategories = [SettingsDefault.uncategorizedSentinel]
                }
            } else {
                selectedCategories.insert(category)
            }
        } label: {
            HStack {
                Text(category)
                Text("\(categoryCounts[category, default: 0])")
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedCategories.contains(category) {
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
                hideCategory(category)
            } label: {
                Image(systemName: "eye.slash")
            }
            .tint(.gray)
            if !protectedCategories.contains(category) {
                Button {
                    categoryToEdit = category
                    editCategoryName = category
                    showingEditAlert = true
                } label: {
                    Image(systemName: "pencil")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            if !protectedCategories.contains(category) {
                Button {
                    categoryToDelete = category
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .contextMenu {
            if !protectedCategories.contains(category) {
                Button {
                    categoryToEdit = category
                    editCategoryName = category
                    showingEditAlert = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.primary)
            }
            Button {
                hideCategory(category)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            .tint(.primary)
            if !protectedCategories.contains(category) {
                Divider()
                Button(role: .destructive) {
                    categoryToDelete = category
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    private func hideCategory(_ category: String) {
        selectedCategories.remove(category)
        if !localHiddenCategories.contains(category) {
            localHiddenCategories.append(category)
            item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty else { return }
        var cats = storedCategories.asCategories
        if !cats.contains(trimmed) {
            cats.append(trimmed)
            storedCategories = cats.asAppStorageString
        }
        selectedCategories.insert(trimmed)
        newCategoryName = ""
    }

    private func renameCategory(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard !trimmed.isEmpty, trimmed != old else { return }
        var cats = storedCategories.asCategories
        if let index = cats.firstIndex(of: old) {
            cats[index] = trimmed
            storedCategories = cats.asAppStorageString
        }
        if selectedCategories.contains(old) {
            selectedCategories.remove(old)
            selectedCategories.insert(trimmed)
        }
        if let idx = localHiddenCategories.firstIndex(of: old) {
            localHiddenCategories[idx] = trimmed
            item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        }
        updateItemsForRenamedCategory(from: old, to: trimmed, modelContext: modelContext)
        NotificationCenter.default.post(
            name: .categoryRenamed,
            object: nil,
            userInfo: ["oldName": old, "newName": trimmed]
        )
    }

    private func deleteCategory(_ category: String) {
        var cats = storedCategories.asCategories
        cats.removeAll { $0 == category }
        storedCategories = cats.asAppStorageString
        selectedCategories.remove(category)
        if selectedCategories.isEmpty {
            selectedCategories = [SettingsDefault.uncategorizedSentinel]
        }
        localHiddenCategories.removeAll { $0 == category }
        item.hiddenFilterCategories = localHiddenCategories.asAppStorageString
        updateItemsForDeletedCategory(category, modelContext: modelContext)
        NotificationCenter.default.post(
            name: .categoryDeleted,
            object: nil,
            userInfo: ["name": category]
        )
    }
}
