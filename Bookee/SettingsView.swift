//
//  SettingsView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("userName") private var userName: String = ""
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true

    @State private var selectedColor: Color = .clear
    @State private var hasLoadedColor = false
    @FocusState private var isUserNameFocused: Bool

    var body: some View {
        Form {
            Section {
                nameField
                sortOrderPicker
                dateFormatPicker
                Toggle(isOn: $showFooters) { Text("Footer Explanations") }
            } header: {
                Text("General")
            } footer: {
                if showFooters {
                    Text("Your 'Name' will appear in the greeting on the main page. 'Sort Order' only affects books on the main page.")
                }
            }

            Section {
                highlightColorButton
                appearancePicker
            } header: {
                Text("Appearance")
            }

            Section {
                trashNavigationLink
                backupsNavigationLink
            } header: {
                Text("Storage")
            }

            Section {
                versionRow
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nameField: some View {
        HStack {
            Text("Name")
            Spacer()
            CursorAtEndTextField_SwiftUI(text: $userName, placeholder: "Optional", onCommit: {
                isUserNameFocused = false
            })
            .multilineTextAlignment(.trailing)
            .focused($isUserNameFocused)
            .trimWhitespaceOnEditingEnd($userName, isFocused: $isUserNameFocused)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isUserNameFocused { isUserNameFocused = true } }
    }

    private var sortOrderPicker: some View {
        Picker(selection: $sortOrder) {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Text(order.rawValue).tag(order)
            }
        } label: {
            Text("Sort Order")
        }
        .pickerStyle(.menu)
    }

    private var dateFormatPicker: some View {
        Picker(selection: $dateFormat) {
            ForEach(DateFormat.allCases, id: \.self) { format in
                Text(format.rawValue).tag(format)
            }
        } label: {
            Text("Date Format")
        }
        .pickerStyle(.menu)
    }

    private var appearancePicker: some View {
        Picker(selection: $appearanceMode) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        } label: {
            Text("Appearance")
        }
        .pickerStyle(.menu)
    }

    private var highlightColorButton: some View {
        ColorPicker(selection: $selectedColor, supportsOpacity: false) { Text("Tint") }
            .onAppear {
                guard !hasLoadedColor else { return }
                hasLoadedColor = true
                selectedColor = highlightColor
            }
            .onChange(of: selectedColor) { _, newValue in
                guard hasLoadedColor else { return }
                let hexValue = newValue.toHex()
                guard hexValue != $highlightColor.wrappedValue else { return }
                $highlightColor.wrappedValue = hexValue
            }
    }

    private var trashNavigationLink: some View {
        NavigationLink { TrashView() } label: { Text("Trash") }
    }

    private var backupsNavigationLink: some View {
        NavigationLink { BackupsView() } label: { Text("Backups") }
    }

    private var versionRow: some View {
        HStack {
            Text("Version")
            Spacer()
            Text("1.0.0").foregroundStyle(.secondary)
        }
    }
}
