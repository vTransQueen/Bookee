//
//  OdometerViews.swift
//  Bookee
//
//  Views for creating and editing per-vehicle odometer readings.
//

import SwiftUI
import PhotosUI

// MARK: - Previous Reading Lookup

/// Latest existing reading for `vehicle` with a date on or before `date` (excluding `excludingID`,
/// used when editing so a reading doesn't compare against itself). Returns nil when no such
/// reading exists yet, so callers can distinguish "no previous reading" (show a placeholder)
/// from "previous reading was 0".
private func previousOdometerReading(for vehicle: String, before date: Date, in readings: [OdometerReading], excluding excludingID: UUID? = nil) -> Int? {
    readings
        .filter { $0.vehicle == vehicle && $0.id != excludingID && $0.date <= date }
        .max { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }?
        .odometerValue
}

/// Earliest existing reading for `vehicle` with a date on or after `date` (excluding
/// `excludingID`). Returns nil when no such reading exists, i.e. this is the most recent
/// reading for the vehicle. Used when editing a reading so its value can be bounded against
/// the reading that follows it, keeping the miles-driven chain non-negative.
private func nextOdometerReading(for vehicle: String, after date: Date, in readings: [OdometerReading], excluding excludingID: UUID? = nil) -> Int? {
    readings
        .filter { $0.vehicle == vehicle && $0.id != excludingID && $0.date >= date }
        .min { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }?
        .odometerValue
}

// MARK: - Calculator-Style Odometer Text Field

/// Plain-integer counterpart to `CalculatorStyleCurrencyTextField`: same cursor-at-end /
/// keyboard-toolbar behavior (via the shared `CursorAtEndTextField_SwiftUI`), but digits are
/// typed as an ordinary left-to-right integer (no cents-shifting), and a nil value shows the
/// placeholder instead of a literal "0".
private struct CalculatorStyleOdometerTextField: View {
    @Binding var value: Int?
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let onCommit: () -> Void

    @State private var textValue: String = ""

    var body: some View {
        CursorAtEndTextField_SwiftUI(text: $textValue, placeholder: placeholder) {
            onCommit()
        }
        .multilineTextAlignment(.trailing)
        .keyboardType(.numberPad)
        .dismissKeyboardOnReturn(true)
        .focused(isFocused)
        .onChange(of: textValue) { _, newValue in
            let digits = String(newValue.filter { $0.isNumber }.prefix(9))
            let formatted = digits.isEmpty ? "" : formatWithCommas(Int(digits) ?? 0)
            if formatted != newValue { textValue = formatted }
            value = digits.isEmpty ? nil : Int(digits)
        }
        .onAppear {
            textValue = value.map(formatWithCommas) ?? ""
        }
        .onChange(of: value) { _, newValue in
            if !isFocused.wrappedValue { textValue = newValue.map(formatWithCommas) ?? "" }
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            if !focused { onCommit() }
        }
    }
}

/// Formats an integer with comma thousands separators (e.g. 12345 -> "12,345").
private func formatWithCommas(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

// MARK: - Shared Odometer Details Section

/// Vehicle / Odometer / Category rows shared by AddOdometerReadingView and EditOdometerReadingView.
private struct OdometerDetailsSection: View {
    @Binding var vehicle: String
    @Binding var odometerValue: Int?
    let vehicles: [String]
    /// The value of the reading immediately before this one (same vehicle), shown read-only
    /// above the Odometer field for reference. Nil when this is the vehicle's first reading.
    let previousValue: Int?
    /// The value of the reading immediately after this one (same vehicle), shown read-only
    /// below the Odometer field. Nil unless this reading falls between two existing readings
    /// (an interior edit, or an add with a date that lands between two existing readings).
    let nextValue: Int?
    let selectedCategories: Set<String>
    let onTapCategories: () -> Void

    @FocusState private var isOdometerFocused: Bool

    var body: some View {
        Section {
            HStack {
                Text("Vehicle")
                Spacer()
                Menu {
                    Picker(selection: $vehicle) {
                        ForEach(vehicles, id: \.self) { v in
                            Text(v).tag(v)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    Text(vehicle.isEmpty ? "Select" : vehicle)
                }
                .tint(.primary)
            }
            .contentShape(Rectangle())

            if let previousValue {
                HStack {
                    Text("Previous Reading")
                    Spacer()
                    Text("\(previousValue) mi")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Odometer")
                Spacer()
                CalculatorStyleOdometerTextField(value: $odometerValue, isFocused: $isOdometerFocused, placeholder: "0") {
                    isOdometerFocused = false
                }
                .frame(width: 125)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { isOdometerFocused = true }

            if let nextValue {
                HStack {
                    Text("Next Reading")
                    Spacer()
                    Text("\(nextValue) mi")
                        .foregroundStyle(.secondary)
                }
            }

            CategoryPickerButton(selectedCategories: selectedCategories, onTap: onTapCategories)
        } header: {
            Text("Odometer Reading")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
}

// MARK: - Shared Odometer Date Section

private struct OdometerDateSection: View {
    @Binding var date: Date

    var body: some View {
        Section {
            HStack {
                Text("Date")
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Shared Add-Item Menu (Vehicle + Attachments)

/// Bottom-toolbar menu combining "add a new vehicle" with the standard Photo/File attachment
/// options, per the odometer sheet's specific ask to fold vehicle creation into the same menu.
private struct OdometerAddItemMenuButton: View {
    @Binding var showingPhotoPicker: Bool
    @Binding var showingFilePicker: Bool
    @Binding var showingAddVehicleAlert: Bool
    var onMenuTap: (() -> Void)?

    var body: some View {
        Menu {
            Button { showingAddVehicleAlert = true } label: { Label("Vehicle", systemImage: "car") }
                .tint(.primary)
            Button { showingPhotoPicker = true } label: { Label("Photo", systemImage: "photo") }
                .tint(.primary)
            Button { showingFilePicker = true } label: { Label("File", systemImage: "doc") }
                .tint(.primary)
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .simultaneousGesture(TapGesture().onEnded { onMenuTap?() })
        .tint(.primary)
    }
}

// MARK: - Shared Add-Vehicle Alert

private extension View {
    /// Attaches a "New Vehicle" text-input alert. `onAdd` receives the trimmed, capitalized name.
    func addVehicleAlert(isPresented: Binding<Bool>, name: Binding<String>, onAdd: @escaping (String) -> Void) -> some View {
        self.alert("New Vehicle", isPresented: isPresented) {
            TextField("Vehicle Name", text: name)
                .textInputAutocapitalization(.words)
            Button("Add") {
                let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
                name.wrappedValue = ""
                guard !trimmed.isEmpty else { return }
                onAdd(trimmed)
            }
            Button("Cancel", role: .cancel) { name.wrappedValue = "" }
        }
    }
}

// MARK: - Add Odometer Reading View

struct AddOdometerReadingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var odometerReadings: [OdometerReading]
    var item: Item

    @State private var vehicle: String
    @State private var odometerValue: Int?
    @State private var date: Date
    @State private var selectedCategories: Set<String> = [SettingsDefault.uncategorizedSentinel]
    @State private var attachments: [Attachment] = []
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingCategoryPicker = false
    @State private var showingAddVehicleAlert = false
    @State private var newVehicleName = ""

    @AppStorage("vehicles") private var storedVehicles: String = "[]"

    // For pre-selecting a specific day when opened from month details
    var selectedMonth: Int?
    var selectedYear: Int?
    var selectedDay: Int?
    var defaultDate: Date?
    // Set by the presenter when restoring a saved `.addOdometerReading` subpage, so this
    // instance reopens with whatever the user had entered rather than a blank form.
    // Consumed and cleared on first appear.
    var initialDraft: Binding<OdometerReadingFormDraft?> = .constant(nil)

    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    init(odometerReadings: Binding<[OdometerReading]>, item: Item, selectedMonth: Int? = nil, selectedYear: Int? = nil, selectedDay: Int? = nil, defaultDate: Date? = nil, initialDraft: Binding<OdometerReadingFormDraft?> = .constant(nil)) {
        self._odometerReadings = odometerReadings
        self.item = item
        self.selectedMonth = selectedMonth
        self.selectedYear = selectedYear
        self.selectedDay = selectedDay
        self.defaultDate = defaultDate
        self.initialDraft = initialDraft

        if let draft = initialDraft.wrappedValue {
            self._vehicle = State(initialValue: draft.vehicle)
            self._odometerValue = State(initialValue: draft.odometerValue)
            self._date = State(initialValue: draft.date)
            self._selectedCategories = State(initialValue: draft.selectedCategories)
            self._attachments = State(initialValue: draft.attachments)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            let initialDate = computeInitialDate(selectedMonth: selectedMonth, selectedYear: selectedYear, selectedDay: selectedDay, defaultDate: defaultDate)
            self._date = State(initialValue: initialDate)

            let existingReadings = odometerReadings.wrappedValue
            let storedVehiclesList = (UserDefaults.standard.string(forKey: "vehicles") ?? "[]").asCategories
            let mostRecentVehicle = existingReadings.max(by: { $0.date < $1.date })?.vehicle
            let initialVehicle = mostRecentVehicle ?? storedVehiclesList.first ?? ""
            self._vehicle = State(initialValue: initialVehicle)
            self._odometerValue = State(initialValue: previousOdometerReading(for: initialVehicle, before: initialDate, in: existingReadings))
        }
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress form survives the app being terminated.
    private var draftSnapshot: OdometerReadingFormDraft {
        OdometerReadingFormDraft(vehicle: vehicle, odometerValue: odometerValue, date: date, selectedCategories: selectedCategories, attachments: attachments, viewingAttachmentID: attachmentToView?.id)
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.odometerReading(snapshot), for: timestamp)
        }
    }

    private var currentPreviousValue: Int? {
        previousOdometerReading(for: vehicle, before: date, in: odometerReadings)
    }

    /// The value of the reading immediately after this one (same vehicle), if any — non-nil
    /// when the chosen date lands between two existing readings for the vehicle.
    private var currentNextValue: Int? {
        nextOdometerReading(for: vehicle, after: date, in: odometerReadings)
    }

    var body: some View {
        Form {
            OdometerDetailsSection(vehicle: $vehicle, odometerValue: $odometerValue, vehicles: storedVehicles.asCategories, previousValue: currentPreviousValue, nextValue: currentNextValue, selectedCategories: selectedCategories) {
                dismissKeyboard()
                showingCategoryPicker = true
            }
            OdometerDateSection(date: $date)

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    draftSaveTask?.cancel()
                    NavigationStateManager.shared.clearDraft()
                    dismiss()
                } label: {
                    Label("Odometer Reading", systemImage: "speedometer")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .tint(.primary)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addReading) {
                    Label("Add", systemImage: "plus")
                }
                .tint(.primary)
                .disabled(vehicle.isEmpty
                          || (odometerValue ?? 0) < (currentPreviousValue ?? 0)
                          || (currentNextValue.map { (odometerValue ?? 0) > $0 } ?? false))
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                OdometerAddItemMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, showingAddVehicleAlert: $showingAddVehicleAlert) {
                    dismissKeyboard()
                }
            }
        }
        .onChange(of: vehicle) { _, newVehicle in
            odometerValue = previousOdometerReading(for: newVehicle, before: date, in: odometerReadings)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if initialDraft.wrappedValue != nil {
                initialDraft.wrappedValue = nil
            } else {
                // A fresh (non-restored) open — clear any draft abandoned by a previous
                // attempt so it's never mistakenly picked up by an unrelated new one.
                NavigationStateManager.shared.clearDraft()
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .navigationDestination(item: $attachmentToView) { attachment in
            AttachmentViewerSheet(attachment: attachment)
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments)
        .navigationDestination(isPresented: $showingCategoryPicker) {
            CategoryPickerView(selectedCategories: $selectedCategories, item: item, month: date.month, year: date.year)
        }
        .addVehicleAlert(isPresented: $showingAddVehicleAlert, name: $newVehicleName) { name in
            addVehicle(name)
        }
    }

    /// Dismisses the odometer field's UIKit-backed keyboard before presenting another sheet.
    private func dismissKeyboard() {
        resignKeyboard()
    }

    private func addVehicle(_ name: String) {
        var vehiclesList = storedVehicles.asCategories
        if !vehiclesList.contains(name) {
            vehiclesList.append(name)
            storedVehicles = vehiclesList.asAppStorageString
        }
        vehicle = name
    }

    private func addReading() {
        let newReading = OdometerReading(vehicle: vehicle, odometerValue: odometerValue ?? 0, date: date, categories: selectedCategories.sorted(), attachments: attachments)
        odometerReadings.append(newReading)
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        dismiss()
    }
}

// MARK: - Edit Odometer Reading View

struct EditOdometerReadingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var reading: OdometerReading
    @Binding var odometerReadings: [OdometerReading]
    var item: Item

    @State private var vehicle: String
    @State private var odometerValue: Int?
    @State private var date: Date
    @State private var selectedCategories: Set<String>
    @State private var attachments: [Attachment]
    @State private var attachmentToView: Attachment?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingCategoryPicker = false
    @State private var showingAddVehicleAlert = false
    @State private var newVehicleName = ""
    @State private var showingDeleteConfirmation = false

    @AppStorage("vehicles") private var storedVehicles: String = "[]"

    // Set by the presenter when restoring a saved in-progress edit (including its nested
    // attachment viewer, if one was open), so this instance reopens with whatever the user
    // had changed rather than the saved reading's original values. Consumed and cleared on
    // first appear.
    var initialDraft: Binding<OdometerReadingFormDraft?> = .constant(nil)
    @State private var hasAppeared = false
    @State private var draftSaveTask: Task<Void, Never>?

    init(reading: Binding<OdometerReading>, odometerReadings: Binding<[OdometerReading]>, item: Item, initialDraft: Binding<OdometerReadingFormDraft?> = .constant(nil)) {
        self._reading = reading
        self._odometerReadings = odometerReadings
        self.item = item
        self.initialDraft = initialDraft

        if let draft = initialDraft.wrappedValue {
            self._vehicle = State(initialValue: draft.vehicle)
            self._odometerValue = State(initialValue: draft.odometerValue)
            self._date = State(initialValue: draft.date)
            self._selectedCategories = State(initialValue: draft.selectedCategories)
            self._attachments = State(initialValue: draft.attachments)
            if let attachmentID = draft.viewingAttachmentID {
                self._attachmentToView = State(initialValue: draft.attachments.first(where: { $0.id == attachmentID }))
            }
        } else {
            let current = reading.wrappedValue
            self._vehicle = State(initialValue: current.vehicle)
            self._odometerValue = State(initialValue: current.odometerValue)
            self._date = State(initialValue: current.date)
            self._selectedCategories = State(initialValue: Set(current.categories))
            self._attachments = State(initialValue: current.attachments)
        }
    }

    /// Snapshot of every field tracked for draft restoration. Any change to it (debounced)
    /// is persisted so the in-progress edit survives the app being terminated.
    private var draftSnapshot: OdometerReadingFormDraft {
        OdometerReadingFormDraft(vehicle: vehicle, odometerValue: odometerValue, date: date, selectedCategories: selectedCategories, attachments: attachments, viewingAttachmentID: attachmentToView?.id)
    }

    private func scheduleDraftSave() {
        let snapshot = draftSnapshot
        let timestamp = item.timestamp
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NavigationStateManager.shared.saveDraft(.odometerReading(snapshot), for: timestamp)
        }
    }

    private var currentPreviousValue: Int? {
        previousOdometerReading(for: vehicle, before: date, in: odometerReadings, excluding: reading.id)
    }

    /// The value of the reading immediately after this one (same vehicle), if any — this
    /// reading's edited value must not exceed it, or the following reading's delta would go negative.
    private var currentNextValue: Int? {
        nextOdometerReading(for: vehicle, after: date, in: odometerReadings, excluding: reading.id)
    }

    var body: some View {
        Form {
            OdometerDetailsSection(vehicle: $vehicle, odometerValue: $odometerValue, vehicles: storedVehicles.asCategories, previousValue: currentPreviousValue, nextValue: currentNextValue, selectedCategories: selectedCategories) {
                dismissKeyboard()
                showingCategoryPicker = true
            }
            OdometerDateSection(date: $date)

            AttachmentManagementView(attachments: $attachments, attachmentToView: $attachmentToView)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    draftSaveTask?.cancel()
                    NavigationStateManager.shared.clearDraft()
                    dismiss()
                } label: {
                    Label("Odometer Reading", systemImage: "speedometer")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .tint(.primary)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: saveReading) {
                    Label("Save", systemImage: "checkmark")
                }
                .tint(.primary)
                .disabled(vehicle.isEmpty
                          || (odometerValue ?? 0) < (currentPreviousValue ?? 0)
                          || (currentNextValue.map { (odometerValue ?? 0) > $0 } ?? false))
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button { showingDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                Spacer()
                OdometerAddItemMenuButton(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, showingAddVehicleAlert: $showingAddVehicleAlert) {
                    dismissKeyboard()
                }
            }
        }
        .navigationDestination(item: $attachmentToView) { attachment in
            AttachmentViewerSheet(attachment: attachment)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if initialDraft.wrappedValue != nil {
                initialDraft.wrappedValue = nil
            } else {
                // A fresh (non-restored) open — clear any draft abandoned by a previous
                // attempt so it's never mistakenly picked up by an unrelated new one.
                NavigationStateManager.shared.clearDraft()
            }
        }
        .onChange(of: draftSnapshot) { _, _ in
            scheduleDraftSave()
        }
        .attachmentPickers(showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker, attachments: $attachments)
        .navigationDestination(isPresented: $showingCategoryPicker) {
            CategoryPickerView(selectedCategories: $selectedCategories, item: item, month: date.month, year: date.year)
        }
        .addVehicleAlert(isPresented: $showingAddVehicleAlert, name: $newVehicleName) { name in
            addVehicle(name)
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert("Delete Odometer Reading?", isPresented: $showingDeleteConfirmation) {
                        Button("Delete", role: .destructive) { performDelete() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete the odometer reading for '\(reading.vehicle)'. This action cannot be undone.")
                    }
            }
        }
    }

    /// Dismisses the odometer field's UIKit-backed keyboard before presenting another sheet.
    private func dismissKeyboard() {
        resignKeyboard()
    }

    private func addVehicle(_ name: String) {
        var vehiclesList = storedVehicles.asCategories
        if !vehiclesList.contains(name) {
            vehiclesList.append(name)
            storedVehicles = vehiclesList.asAppStorageString
        }
        vehicle = name
    }

    private func saveReading() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        reading.vehicle = vehicle
        reading.odometerValue = odometerValue ?? 0
        reading.date = date
        reading.categories = selectedCategories.sorted()
        reading.attachments = attachments
        dismiss()
    }

    private func performDelete() {
        draftSaveTask?.cancel()
        NavigationStateManager.shared.clearDraft()
        odometerReadings.removeAll { $0.id == reading.id }
        dismiss()
    }
}
