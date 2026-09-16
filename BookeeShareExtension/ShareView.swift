//
//  ShareView.swift
//  BookeeShareExtension
//
//  Confirmation sheet for the Share Extension.
//  Lets the user pick which budget to attach to and which month/year to file under.
//

import SwiftUI

struct ShareView: View {
    let budgets: [(name: String, timestamp: Double)]
    let onAdd: (Double, Int, Int) -> Void   // (budgetTimestamp, month, year)
    let onCancel: () -> Void

    @State private var selectedTimestamp: Double
    @State private var selectedMonth: Int
    @State private var selectedYear: Int
    @State private var isAdding = false

    init(
        budgets: [(name: String, timestamp: Double)],
        pinnedTimestamp: Double,
        onAdd: @escaping (Double, Int, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.budgets = budgets
        self.onAdd = onAdd
        self.onCancel = onCancel
        let defaultTs = (pinnedTimestamp > 0 ? pinnedTimestamp : budgets.first?.timestamp) ?? 0
        _selectedTimestamp = State(initialValue: defaultTs)
        _selectedMonth     = State(initialValue: Calendar.current.component(.month, from: Date()))
        _selectedYear      = State(initialValue: Calendar.current.component(.year,  from: Date()))
    }

    private var yearRange: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 3)...(y + 1))
    }

    private static let monthNames: [String] = {
        let fmt = DateFormatter()
        fmt.locale = .current
        return fmt.monthSymbols ?? [
            "January","February","March","April","May","June",
            "July","August","September","October","November","December"
        ]
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────────
                VStack(spacing: 6) {
                    Image(systemName: "paperclip.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.pink)
                        .padding(.top, 20)

                    if budgets.isEmpty {
                        Text("No Budgets Found")
                            .font(.headline)
                            .padding(.top, 4)
                        Text("Create a budget in Bookee first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add to Budget")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $selectedTimestamp) {
                            ForEach(budgets, id: \.timestamp) { budget in
                                Text(budget.name).tag(budget.timestamp)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.primary)
                    }
                }
                .padding(.bottom, 16)

                Divider()

                // ── Month / Year wheels ──────────────────────────────────
                HStack(spacing: 0) {
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(Self.monthNames[m - 1]).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Year", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    .clipped()
                }
                .frame(height: 150)
                .disabled(budgets.isEmpty)

                Divider()

                Spacer()
            }
            .navigationTitle("Bookee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isAdding = true
                        onAdd(selectedTimestamp, selectedMonth, selectedYear)
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .fontWeight(.semibold)
                    .disabled(budgets.isEmpty || selectedTimestamp == 0 || isAdding)
                }
            }
        }
    }
}
