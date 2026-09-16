//
//  BudgetDetailsView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

struct BudgetDetailsView: View {
    @Bindable var item: Item
    var shouldFocusOnTitle: Bool = false
    var isEditingDuplicatedItem: Bool = false  // Indicates this view is editing a newly duplicated item
    var originalDuplicatedItemName: String = ""  // Original name to prevent saving without modification
    // Set by the presenter when restoring a saved `.budgetDetailsTrash` subpage, so this
    // instance auto-opens Budget Trash on first appear. Consumed and cleared immediately.
    var restoreBudgetTrash: Binding<Bool> = .constant(false)
    // Set by the presenter when restoring a saved in-progress edit, so this instance reopens
    // with whatever the user had changed rather than the budget's saved values. Consumed and
    // cleared on first appear.
    var initialDraft: Binding<BudgetDetailsDraft?> = .constant(nil)
    var onSave: (() -> Void)? = nil  // Closure executed when Done is tapped
    var onCancel: (() -> Void)? = nil  // Closure executed when Cancel is tapped

    @State private var showingBudgetTrash = false
    @State private var draftSaveTask: Task<Void, Never>?

    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    // Local editing state - changes staged here until Done is tapped
    @State private var name: String = ""
    @State private var taxSavingsPercentage: Double = 0.0
    @State private var isTaxSavingsEnabled: Bool = false
    @State private var lastTaxSavingsPercentage: Double = 0.0  // Preserved when tax savings is toggled off/on

    // Calendar settings
    @State private var calendarWeekStartDay: Int = 1

    @State private var taxSavingsText = ""
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isTaxFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext

    // Original values captured on appear - used to detect changes before saving
    @State private var originalName: String = ""
    @State private var originalTaxSavingsPercentage: Double = 0.0
    @State private var originalIsTaxSavingsEnabled: Bool = false

    // Original calendar settings for change detection
    @State private var originalCalendarWeekStartDay: Int = 1

    @State private var showingDeleteConfirmation = false

    // Guards initializeDisplayValues() so returning from a pushed page (e.g. Budget Trash)
    // doesn't overwrite the staged edits with the item's on-disk values again.
    @State private var hasAppeared = false

    // Prevents saving duplicated items without renaming
    var isDoneButtonDisabled: Bool {
        isEditingDuplicatedItem && !originalDuplicatedItemName.isEmpty && name == originalDuplicatedItemName
    }


    var body: some View {
        Form {
            nameSection

            taxesSection
            calendarSection

            storageSection
            informationSection
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditingDuplicatedItem)
        .toolbar {
            if isEditingDuplicatedItem {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        revertChanges()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .tint(.primary)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    revertChanges()
                } label: {
                    Label("Edit Budget", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .tint(.primary)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    saveChanges()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.primary)
                .disabled(isDoneButtonDisabled)
            }
        }
        .navigationDestination(isPresented: $showingBudgetTrash) {
            BudgetTrashView(item: item)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            initializeDisplayValues()

            // Focus title field when duplicating to prompt immediate rename
            if shouldFocusOnTitle {
                isNameFieldFocused = true
            }

            if restoreBudgetTrash.wrappedValue {
                // No user tap or in-flight transition to wait out here — the page should
                // just already be open.
                withoutAnimation {
                    showingBudgetTrash = true
                }
                restoreBudgetTrash.wrappedValue = false
            }

            if initialDraft.wrappedValue != nil {
                initialDraft.wrappedValue = nil
            } else if !isEditingDuplicatedItem {
                // A fresh (non-restored) open — clear any draft abandoned by a previous
                // attempt so it's never mistakenly picked up by an unrelated new one. Skipped
                // while editing a brand new/duplicated item, since that flow's own item isn't
                // a stable restoration target anyway (see ContentView's isEditingDuplicatedItem
                // guard around saveSubpage).
                NavigationStateManager.shared.clearDraft()
            }
        }
        .onChange(of: showingBudgetTrash) { _, isShowing in
            NavigationStateManager.shared.saveSubpage(isShowing ? .budgetDetailsTrash : .budgetDetails, for: item.timestamp)
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .onChange(of: isTaxFieldFocused) { _, newValue in
            // Apply tax percentage formatting when user leaves field
            if !newValue && !taxSavingsText.isEmpty {
                updateTaxPercentage()
            }
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert("Move to Trash?", isPresented: $showingDeleteConfirmation) {
                        Button("Confirm", role: .destructive) { performDelete() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will move '\(name)' to the trash. You can restore it from the trash within 30 days.")
                    }
            }
        }
    }

    // MARK: - View Sections

    private var nameSection: some View {
        Section {
            HStack {
                Text("Title")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $name, placeholder: "Budget")
                    .multilineTextAlignment(.trailing)
                    .focused($isNameFieldFocused)
                    .textInputAutocapitalization(.words)
                    .trimWhitespaceOnEditingEnd($name, isFocused: $isNameFieldFocused)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isNameFieldFocused = true
            }
        } header: {
            Text("Budget Details")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }

    private var taxesSection: some View {
        Section {
            Toggle("Taxes", isOn: $isTaxSavingsEnabled)
                .onChange(of: isTaxSavingsEnabled) { _, newValue in
                    // Dismiss keyboard to prevent UI conflicts during toggle
                    dismissKeyboard()

                    if !newValue {
                        // Preserve current percentage and clear field when disabled
                        if taxSavingsPercentage.isEffectivelyPositive {
                            lastTaxSavingsPercentage = taxSavingsPercentage
                        }
                        taxSavingsPercentage = 0.0
                        taxSavingsText = ""
                        isTaxFieldFocused = false
                    } else {
                        // Restore previously saved percentage when re-enabled
                        if lastTaxSavingsPercentage.isEffectivelyPositive {
                            taxSavingsPercentage = lastTaxSavingsPercentage
                            taxSavingsText = PercentageFormatter.formatForTextField(lastTaxSavingsPercentage)
                        }
                    }
                }

            HStack(spacing: 2) {
                Text("Percentage")
                Spacer()
                CursorAtEndTextField_SwiftUI(text: $taxSavingsText, placeholder: "0.0")
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($isTaxFieldFocused)
                    .onChange(of: taxSavingsText) { oldValue, newValue in
                        formatTaxPercentage(oldValue: oldValue, newValue: newValue)
                    }
                    .disabled(!isTaxSavingsEnabled)
                    .opacity(isTaxSavingsEnabled ? 1.0 : 0.5)
                Text("%")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isTaxSavingsEnabled {
                    isTaxFieldFocused = true
                }
            }
        }
    }

    private var calendarSection: some View {
        Section {
            Picker("Week Starts On", selection: $calendarWeekStartDay) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
                Text("Tuesday").tag(3)
                Text("Wednesday").tag(4)
                Text("Thursday").tag(5)
                Text("Friday").tag(6)
                Text("Saturday").tag(7)
            }
            .pickerStyle(.menu)
            .onChange(of: calendarWeekStartDay) { _, _ in dismissKeyboard() }

        }
    }

    private var informationSection: some View {
        Section {
            HStack {
                Text("Created")
                Spacer()
                Text(item.timestamp, format: dateFormat.styleWithTime)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageSection: some View {
        Section {
            Button {
                showingBudgetTrash = true
            } label: {
                HStack {
                    Text("Budget Trash")
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

    // MARK: - Initialization and Formatting

    private func dismissKeyboard() {
        isNameFieldFocused = false
        isTaxFieldFocused = false
    }

    private func initializeDisplayValues() {
        if let draft = initialDraft.wrappedValue {
            // Restoring an in-progress edit — seed the staged (editable) fields from it.
            name = draft.name
            taxSavingsPercentage = draft.taxSavingsPercentage
            isTaxSavingsEnabled = draft.isTaxSavingsEnabled
            lastTaxSavingsPercentage = draft.lastTaxSavingsPercentage
            calendarWeekStartDay = draft.calendarWeekStartDay
            if draft.taxSavingsPercentage.isEffectivelyPositive {
                taxSavingsText = PercentageFormatter.formatForTextField(draft.taxSavingsPercentage)
            }
        } else {
            // Fresh open — load item values into local state for editing.
            name = item.name
            taxSavingsPercentage = item.taxSavingsPercentage.roundedMoney()
            isTaxSavingsEnabled = item.isTaxSavingsEnabled

            // Determine last tax savings percentage with fallback logic:
            // 1. If disabled but value was stored, use stored value
            // 2. If stored value exists and is positive, use it
            // 3. If current percentage is positive, use it
            // 4. Default to 0.0
            let storedLast = item.effectiveLastTaxSavingsPercentage
            if storedLast.isEffectivelyPositive {
                lastTaxSavingsPercentage = storedLast.roundedMoney()
            } else if item.taxSavingsPercentage.isEffectivelyPositive {
                lastTaxSavingsPercentage = item.taxSavingsPercentage.roundedMoney()
            } else {
                lastTaxSavingsPercentage = 0.0
            }

            // Populate text field if percentage exists
            if item.taxSavingsPercentage.isEffectivelyPositive {
                taxSavingsText = PercentageFormatter.formatForTextField(item.taxSavingsPercentage)
            }

            // Load calendar settings
            calendarWeekStartDay = item.effectiveCalendarWeekStartDay
        }

        // Original values are always anchored to the true model, regardless of a restored
        // draft, since change detection must compare against what's actually saved.
        originalName = item.name
        originalTaxSavingsPercentage = item.taxSavingsPercentage.roundedMoney()
        originalIsTaxSavingsEnabled = item.isTaxSavingsEnabled
        originalCalendarWeekStartDay = item.effectiveCalendarWeekStartDay
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress edit survives the app being terminated.
    private var draftSnapshot: BudgetDetailsDraft {
        BudgetDetailsDraft(
            name: name, taxSavingsPercentage: taxSavingsPercentage, isTaxSavingsEnabled: isTaxSavingsEnabled,
            lastTaxSavingsPercentage: lastTaxSavingsPercentage, calendarWeekStartDay: calendarWeekStartDay
        )
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.budgetDetails(snapshot), for: timestamp)
        }
    }

    private func formatTaxPercentage(oldValue: String, newValue: String) {
        // Format input using PercentageFormatter and clamp to 0-100 range
        taxSavingsText = PercentageFormatter.format(
            oldValue: oldValue,
            newValue: newValue,
            percentage: &taxSavingsPercentage,
            maxValue: 100
        )
        taxSavingsText = taxSavingsText.replacingOccurrences(of: "%", with: "")

        // Update preserved percentage whenever user enters valid value
        if taxSavingsPercentage.isEffectivelyPositive {
            lastTaxSavingsPercentage = taxSavingsPercentage
        }
    }

    private func updateTaxPercentage() {
        // Convert text input to numeric value, clamped to 100% maximum
        if let value = Double(taxSavingsText) {
            taxSavingsPercentage = min(value, 100).roundedMoney()
            taxSavingsText = PercentageFormatter.formatForTextField(taxSavingsPercentage)

            // Update preserved percentage whenever user enters valid value
            if taxSavingsPercentage.isEffectivelyPositive {
                lastTaxSavingsPercentage = taxSavingsPercentage
            }
        }
    }

    // MARK: - Persistence

    // Commits all staged changes to the item and saves to SwiftData
    public func saveChanges() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        // Compare current values with original to detect modifications
        let hasChanges = name != originalName ||
                        !taxSavingsPercentage.isEffectivelyEqual(to: originalTaxSavingsPercentage) ||
                        isTaxSavingsEnabled != originalIsTaxSavingsEnabled ||
                        calendarWeekStartDay != originalCalendarWeekStartDay

        if hasChanges {
            // Write all changes to the item model
            item.name = name
            item.taxSavingsPercentage = taxSavingsPercentage
            item.isTaxSavingsEnabled = isTaxSavingsEnabled
            item.lastTaxSavingsPercentage = lastTaxSavingsPercentage  // Preserve for toggle restoration
            item.calendarWeekStartDay = calendarWeekStartDay == 1 ? nil : calendarWeekStartDay
            item.lastModifiedDate = Date()

            // Persist to SwiftData context
            item.modelContext?.saveWithLogging("BudgetDetailsView: Saved changes")

            // Execute save closure
            onSave?()
        } else {
            print("⏭️ BudgetDetailsView: No changes detected, skipping save")
            onSave?()  // Execute closure anyway for cleanup/dismissal
        }
    }

    // Discards staged changes without modifying the item
    public func revertChanges() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        // No revert needed since changes are staged locally
        // Execute cancel closure for cleanup/dismissal
        onCancel?()
    }

    private func performDelete() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        item.deletedDate = Date()
        item.modelContext?.saveWithLogging("BudgetDetailsView: Item moved to trash")
        onCancel?()
    }
}
