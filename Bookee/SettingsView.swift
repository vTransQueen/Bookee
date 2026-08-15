//
//  SettingsView.swift
//  K Test
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Item> { $0.deletedDate != nil })
    private var deletedItems: [Item]
    
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("userName") private var userName: String = ""
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true
    
    @State private var selectedColor: Color = .clear
    @State private var hasLoadedColor = false
    @FocusState private var isUserNameFocused: Bool
    
    // MARK: - View Body
    
    var body: some View {
        Form {
            Section {
                nameField
                currencyPicker
                sortOrderPicker
                dateFormatPicker
                Toggle("Footer Explanations", isOn: $showFooters)
            } header: {
                Text("General")
            } footer: {
                if showFooters {
                    Text("Your 'Name' will appear in the greeting on the main page. 'Sort Order' only affects items on the main page.")
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

    // MARK: - View Components
    
    /// Text field for user's name with tap-to-focus behavior and automatic whitespace trimming
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
        .onTapGesture {
            if !isUserNameFocused {
                isUserNameFocused = true
            }
        }
    }
    
    private var currencyPicker: some View {
        Picker("Currency", selection: $selectedCurrency) {
            ForEach(Currency.allCases, id: \.self) { currency in
                Text("\(currency.symbol) \(currency.code)").tag(currency)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var sortOrderPicker: some View {
        Picker("Sort Order", selection: $sortOrder) {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Text(order.rawValue).tag(order)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var dateFormatPicker: some View {
        Picker("Date Format", selection: $dateFormat) {
            ForEach(DateFormat.allCases, id: \.self) { format in
                Text(format.rawValue).tag(format)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var appearancePicker: some View {
        Picker("Appearance", selection: $appearanceMode) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }
    
    /// Color picker for the app's tint color with hex persistence to AppStorage
    /// Handles initial load from hex string and saves changes back as hex
    private var highlightColorButton: some View {
        ColorPicker("Tint", selection: $selectedColor, supportsOpacity: false)
            .onAppear {
                // Load color from hex string only once on first appearance to prevent update loops
                guard !hasLoadedColor else { return }
                hasLoadedColor = true
                
                print("🎨 onAppear - Loading color from hex: \($highlightColor.wrappedValue)")
                selectedColor = highlightColor
            }
            .onChange(of: selectedColor) { oldValue, newValue in
                // Wait until initial load is complete before saving changes
                guard hasLoadedColor else { return }

                // Convert to hex and save to AppStorage
                let hexValue = newValue.toHex()
                // Prevent saving if value hasn't actually changed (avoids update loops)
                guard hexValue != $highlightColor.wrappedValue else { return }

                print("🎨 Color changed - Old: \(oldValue.toHex()), New: \(hexValue)")
                $highlightColor.wrappedValue = hexValue
            }
    }
    
    private var trashNavigationLink: some View {
        NavigationLink("Trash") {
            TrashView()
        }
    }
    
    private var backupsNavigationLink: some View {
        NavigationLink("Backups") {
            BackupsView()
        }
    }
    
    private var versionRow: some View {
        HStack {
            Text("Version")
            Spacer()
            Text("1.0.0")
                .foregroundStyle(.secondary)
        }
    }
}


