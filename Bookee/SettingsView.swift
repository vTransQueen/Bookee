//
//  SettingsView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @HighlightColorStorage private var highlightColor
    
    // MARK: - View Body
    
    var body: some View {
        Form {
            Section {
                currencyPicker
                sortOrderPicker
                dateFormatPicker
            } header: {
                Text("App Details")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .textCase(nil)
            }
            
            Section {
                highlightColorButton
                appearancePicker
            }
            
            Section {
                backupsNavigationLink
                trashNavigationLink
            }
            
            Section {
                versionRow
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            PageNavigationToolbarItem(label: "Settings", systemImage: "gear", titleOnly: true)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { NavigationStateManager.shared.showingUniversalSearch = true } } label: {
                    Image(systemName: "magnifyingglass")
                }
                .tint(.primary)
            }
        }
    }

    // MARK: - View Components
    
    private var sortOrderPicker: some View {
        Picker("Sort Order", selection: $sortOrder) {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Text(order.rawValue).tag(order)
            }
        }
        .pickerStyle(.menu)
    }

    private var currencyPicker: some View {
        Picker("Currency", selection: $selectedCurrency) {
            ForEach(Currency.allCases, id: \.self) { currency in
                Text("\(currency.symbol) \(currency.code)").tag(currency)
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
    
    private var highlightColorButton: some View {
        ColorPicker("Tint", selection: $highlightColor, supportsOpacity: false)
    }
    
    private var trashNavigationLink: some View {
        NavigationLink("Home Trash", value: NavDestination.trash)
    }
    
    private var backupsNavigationLink: some View {
        NavigationLink("Backups", value: NavDestination.backups)
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


