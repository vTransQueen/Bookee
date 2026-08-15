//
//  SharedComponents.swift
//  Bookee
//
//  Shared view components and helpers used across multiple views.
//

import SwiftUI

// MARK: - Alert Container

/// Wraps content and applies primary tint so alerts stay neutral regardless of any custom highlight color
/// applied to a parent view. Used by Add/Edit views, attachment management views, trash, and backups.
struct AlertContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .tint(.primary)
    }
}

// MARK: - Empty State Placeholder

/// Reusable empty-state view with an icon, title, and optional message.
/// Used by TrashView, CategoryPickerView, and ContentView for their empty states.
struct EmptyStatePlaceholder: View {
    let systemImage: String
    let title: String
    let message: String?

    init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Year Picker Menu

/// A compact Menu that lets the user pick a year from the past 25 years.
/// Used by BudgetIncomeSheetView and BudgetVisualizerPageView.
struct YearPickerMenu: View {
    @Binding var selectedYear: Int
    var label: String = "Year"

    var body: some View {
        let currentYear = Date().year
        let startYear = currentYear - 24
        Menu {
            ForEach((startYear...currentYear).reversed(), id: \.self) { year in
                Button(String(year)) { selectedYear = year }
            }
        } label: {
            Text(String(selectedYear))
        }
    }
}

// MARK: - Selection Mode Toolbar

/// ToolbarContent for selection mode: Select All / Deselect All on the trailing side
/// and a Delete button on the bottom bar. Used by ContentView, TrashView, and BudgetVisualizerPageView.
struct SelectionModeToolbar: ToolbarContent {
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onDelete: () -> Void
    var deleteLabel: String = "Delete"

    private var selectAllTitle: String {
        selectedCount == totalCount ? "Deselect All" : "Select All"
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(selectAllTitle) {
                if selectedCount == totalCount { onDeselectAll() } else { onSelectAll() }
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button(role: .destructive, action: onDelete) {
                Label(deleteLabel, systemImage: "trash")
            }
            .disabled(selectedCount == 0)
        }
    }
}

// MARK: - Highlightable Budget Overview Row

private struct HighlightableBudgetOverviewRow: View {
    let label: String
    let value: Double
    let color: Color
    let rowID: String
    let selectedCurrency: Currency
    let onTap: () -> Void

    @HighlightColorStorage private var highlightColor
    @State private var isHighlighted = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top) {
                Text(label).fontWeight(.medium)
                    .foregroundStyle(isHighlighted ? highlightColor : .primary)
                Spacer()
                Text(value, format: .currency(code: selectedCurrency.code))
                    .foregroundStyle(isHighlighted ? highlightColor : color)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(rowID)
        .animation(.default, value: isHighlighted)
        .onReceive(NotificationCenter.default.publisher(for: .highlightBudgetOverviewRow)) { note in
            guard let id = note.object as? String, id == rowID else { return }
            isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isHighlighted = false }
        }
    }
}

// MARK: - Month Overview Rows View

/// Shared row content for BudgetVisualizerPageView's monthly overview section and
/// per-month rows. When `yearMonth` is non-nil, rows are wrapped in tappable Buttons
/// that navigate to that month; otherwise they are plain static HStacks.
struct MonthOverviewRowsView: View {
    let m: BudgetVisualizerPageView.MonthMetrics
    let item: Item
    let selectedCurrency: Currency
    let yearMonth: YearMonth?
    let navigationPath: Binding<NavigationPath>?

    var body: some View {
        Group {
            if item.effectiveShowReallocationsRow {
                row("Reallocated", value: m.positiveReallocation, color: .green, id: "other-income")
            }
            if item.isTaxSavingsEnabled {
                if item.effectiveShowOtherIncomeRow {
                    row("Other Income",
                        value: item.effectiveShowReallocationsRow ? m.untaxableIncome : roundMoney(m.untaxableIncome + m.positiveReallocation),
                        color: .green, id: "Nontaxable-income")
                    row("Taxable Income", value: m.taxableIncome, color: .green, id: "taxable-income")
                } else {
                    row("Income",
                        value: item.effectiveShowReallocationsRow
                            ? roundMoney(m.taxableIncome + m.untaxableIncome)
                            : roundMoney(roundMoney(m.taxableIncome + m.untaxableIncome) + m.positiveReallocation),
                        color: .green, id: "taxable-income")
                }
            } else {
                row("Income",
                    value: item.effectiveShowReallocationsRow ? m.untaxableIncome : roundMoney(m.untaxableIncome + m.positiveReallocation),
                    color: .green, id: "Nontaxable-income")
            }
            if item.isTaxSavingsEnabled && item.effectiveShowTaxesGoalRow {
                row("Tax Savings", value: m.taxSavings, color: .orange, id: "tax-savings")
            }
            if item.effectiveShowExpensesRow {
                let mergedTax = item.isTaxSavingsEnabled && !item.effectiveShowTaxesGoalRow ? m.taxSavings : 0.0
                row("Expenses",
                    value: item.effectiveShowReallocationsRow
                        ? roundMoney(m.expenses + mergedTax)
                        : roundMoney(roundMoney(m.expenses + m.negativeReallocation) + mergedTax),
                    color: .red, id: "expenses")
            }
            if item.effectiveShowReallocationsRow {
                row("Reallocated", value: m.negativeReallocation, color: .red, id: "removed-from")
            }
            if item.effectiveShowIncomeSurplusRow {
                neededExcessRow()
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, value: Double, color: Color, id: String) -> some View {
        if let ym = yearMonth {
            HighlightableBudgetOverviewRow(
                label: label,
                value: value,
                color: color,
                rowID: "\(id)-\(ym.year)-\(ym.month)",
                selectedCurrency: selectedCurrency,
                onTap: { navigationPath?.wrappedValue.append(ym) }
            )
        } else {
            HStack(alignment: .top) {
                Text(label)
                Spacer()
                Text(value, format: .currency(code: selectedCurrency.code)).foregroundStyle(color)
            }
        }
    }

    @ViewBuilder
    private func neededExcessRow() -> some View {
        if let ym = yearMonth {
            Button { navigationPath?.wrappedValue.append(ym) } label: {
                neededExcessContent(medium: true)
            }
            .buttonStyle(.plain)
            .id("surplus-\(ym.year)-\(ym.month)")
        } else {
            neededExcessContent(medium: false)
        }
    }

    @ViewBuilder
    private func neededExcessContent(medium: Bool) -> some View {
        HStack(alignment: .top) {
            if m.remaining.isEffectivelyPositive {
                Text("Excess Income").if(medium) { $0.fontWeight(.medium) }
                Spacer()
                Text(m.remaining, format: .currency(code: selectedCurrency.code))
                    .foregroundStyle(.green).if(medium) { $0.fontWeight(.medium) }
            } else if m.remaining.isEffectivelyZero {
                Text("Needed Income").if(medium) { $0.fontWeight(.medium) }
                Spacer()
                Text(0.0, format: .currency(code: selectedCurrency.code))
                    .foregroundStyle(.indigo).if(medium) { $0.fontWeight(.medium) }
            } else {
                Text("Needed Income").if(medium) { $0.fontWeight(.medium) }
                Spacer()
                HStack(spacing: 4) {
                    Text(m.breakEven, format: .currency(code: selectedCurrency.code))
                        .foregroundStyle(.indigo).if(medium) { $0.fontWeight(.medium) }
                    if item.isTaxSavingsEnabled {
                        Text("/").foregroundStyle(.primary)
                        Text(m.incomeNeeded, format: .currency(code: selectedCurrency.code))
                            .foregroundStyle(.indigo).if(medium) { $0.fontWeight(.medium) }
                    }
                }
            }
        }
        .if(medium) { $0.contentShape(Rectangle()) }
    }
}
