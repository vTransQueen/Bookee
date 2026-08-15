//
//  BudgetDetailsView.swift
//  K Test
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
    var onSave: (() -> Void)? = nil  // Closure executed when Done is tapped
    var onCancel: (() -> Void)? = nil  // Closure executed when Cancel is tapped
    
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("showFooters") private var showFooters: Bool = true
    
    // Local editing state - changes staged here until Done is tapped
    @State private var name: String = ""
    @State private var taxSavingsPercentage: Double = 0.0
    @State private var isTaxSavingsEnabled: Bool = false
    @State private var lastTaxSavingsPercentage: Double = 0.0  // Preserved when tax savings is toggled off/on
    
    // Monthly overview display toggles
    @State private var showExpensesRow: Bool = true
    @State private var showReallocationsRow: Bool = true
    @State private var showTaxSavingsRow: Bool = true
    
    @State private var taxSavingsText = ""
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isTaxFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Item> { $0.deletedDate == nil })
    private var allNonDeletedItems: [Item]
    
    // Original values captured on appear - used to detect changes before saving
    @State private var originalName: String = ""
    @State private var originalTaxSavingsPercentage: Double = 0.0
    @State private var originalIsTaxSavingsEnabled: Bool = false
    
    // Original monthly overview display values for change detection
    @State private var originalShowReallocationsRow: Bool = true
    @State private var originalShowTaxSavingsRow: Bool = true
    @State private var showingDeleteConfirmation = false

    // Prevents saving duplicated items without renaming
    var isDoneButtonDisabled: Bool {
        isEditingDuplicatedItem && !originalDuplicatedItemName.isEmpty && name == originalDuplicatedItemName
    }

    
    var body: some View {
        Form {
            nameSection
            
            if item.itemType == .budget {
                taxesSection
                monthlyOverviewDisplaySection
            }
            
            informationSection
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Edit Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    revertChanges()
                } label: {
                    Label("Cancel", systemImage: "xmark")
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

            if !isEditingDuplicatedItem {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .onAppear {
            initializeDisplayValues()
            
            // Focus title field when duplicating to prompt immediate rename
            if shouldFocusOnTitle {
                isNameFieldFocused = true
            }
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
                        Button("Delete", role: .destructive) { performDelete() }
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
                CursorAtEndTextField_SwiftUI(text: $name, placeholder: item.itemType == .income ? "Income Tracker" : "Budget Visualizer")
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
            Text(item.itemType == .income ? "Income Details" : "Budget Details")
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
        } header: {
            Text("Taxes")
        } footer: {
            if showFooters {
                Text("Toggling off 'Taxes' disables all tax options.")
            }
        }
    }

    private var monthlyOverviewDisplaySection: some View {
        Section {
            if isTaxSavingsEnabled {
                Toggle("Tax Savings", isOn: $showTaxSavingsRow)
                    .onChange(of: showTaxSavingsRow) { _, _ in dismissKeyboard() }
            }

            Toggle("Reallocations", isOn: $showReallocationsRow)
                .onChange(of: showReallocationsRow) { _, _ in dismissKeyboard() }
        } header: {
            Text("Monthly Overview")
        } footer: {
            if showFooters {
                Text("Toggle which rows are displayed in the monthly overview.")
            }
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
        } header: {
            Text("Information")
        }
    }
    
    // MARK: - Initialization and Formatting
    
    private func dismissKeyboard() {
        isNameFieldFocused = false
        isTaxFieldFocused = false
    }
    
    private func initializeDisplayValues() {
        // Load item values into local state for editing
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
        
        // Load monthly overview display preferences
        showReallocationsRow = item.effectiveShowReallocationsRow
        showTaxSavingsRow = item.effectiveShowTaxesGoalRow

        // Populate text field if percentage exists
        if item.taxSavingsPercentage.isEffectivelyPositive {
            taxSavingsText = PercentageFormatter.formatForTextField(item.taxSavingsPercentage)
        }
        
        // Snapshot original values for later comparison
        originalName = item.name
        originalTaxSavingsPercentage = item.taxSavingsPercentage.roundedMoney()
        originalIsTaxSavingsEnabled = item.isTaxSavingsEnabled
        
        // Snapshot original display settings
        originalShowReallocationsRow = item.effectiveShowReallocationsRow
        originalShowTaxSavingsRow = item.effectiveShowTaxesGoalRow
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
        // Compare current values with original to detect modifications
        let hasChanges = name != originalName ||
                        taxSavingsPercentage != originalTaxSavingsPercentage ||
                        isTaxSavingsEnabled != originalIsTaxSavingsEnabled ||
                        showReallocationsRow != originalShowReallocationsRow ||
                        showTaxSavingsRow != originalShowTaxSavingsRow
        
        if hasChanges {
            // Write all changes to the item model
            item.name = name
            item.taxSavingsPercentage = taxSavingsPercentage
            item.isTaxSavingsEnabled = isTaxSavingsEnabled
            item.lastTaxSavingsPercentage = lastTaxSavingsPercentage  // Preserve for toggle restoration
            // Convert show toggles to hide flags for storage
            item.hideExpensesRow = false  // Expenses always visible
            item.hideReallocationsRow = !showReallocationsRow
            item.hideOtherIncomeRow = !showTaxSavingsRow  // Other Income follows Tax Savings
            item.hideTaxesGoalRow = !showTaxSavingsRow
            item.hideIncomeSurplusRow = false  // Excess/Needed Income always visible
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
        // No revert needed since changes are staged locally
        // Execute cancel closure for cleanup/dismissal
        onCancel?()
    }

    private func performDelete() {
        item.deletedDate = Date()
        item.modelContext?.saveWithLogging("BudgetDetailsView: Item moved to trash")
        onCancel?()
        dismiss()
    }
}
