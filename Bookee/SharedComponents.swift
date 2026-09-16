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

// MARK: - Page Navigation Toolbar Item

/// Leading toolbar button that shows the current page name and navigates back one page.
struct PageNavigationToolbarItem: ToolbarContent {
    let label: String
    let systemImage: String
    var placement: ToolbarItemPlacement = .navigationBarLeading
    var titleOnly: Bool = false
    var disabled: Bool = false

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button {
                NavigationStateManager.shared.goBack()
            } label: {
                Group {
                    if titleOnly {
                        Label(label, systemImage: systemImage)
                            .labelStyle(.titleOnly)
                    } else {
                        Label(label, systemImage: systemImage)
                    }
                }
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
            }
            .tint(.primary)
            .disabled(disabled)
        }
    }
}

// MARK: - Highlightable Budget Overview Row

private struct HighlightableBudgetOverviewRow: View {
    let label: String
    let value: Decimal
    let color: Color
    let rowID: String
    let selectedCurrency: Currency
    let onTap: () -> Void

    @HighlightColorStorage private var highlightColor
    @State private var isHighlighted = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                rowContent(highlighted: false)
                    .opacity(isHighlighted ? 0 : 1)
                    .animation(.easeInOut(duration: 0.5), value: isHighlighted)
                rowContent(highlighted: true)
                    .opacity(isHighlighted ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: isHighlighted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(rowID)
        .onReceive(NotificationCenter.default.publisher(for: .highlightBudgetOverviewRow)) { note in
            guard let id = note.object as? String, id == rowID else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isHighlighted = true
                try? await Task.sleep(for: .milliseconds(1550))
                isHighlighted = false
            }
        }
    }

    @ViewBuilder
    private func rowContent(highlighted: Bool) -> some View {
        HStack(alignment: .top) {
            Text(label).fontWeight(.medium)
                .foregroundStyle(highlighted ? highlightColor : Color.primary)
            Spacer()
            Text(value, format: .currency(code: selectedCurrency.code))
                .foregroundStyle(highlighted ? highlightColor : color)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Month Metrics

struct MonthMetrics {
    let taxableIncome: Decimal
    let untaxableIncome: Decimal
    let expenses: Decimal
    let reallocated: Decimal
    let positiveReallocation: Decimal
    let negativeReallocation: Decimal
    let incomeNeeded: Decimal
    let breakEven: Decimal
    let remaining: Decimal
    let taxSavings: Decimal

    static let empty = MonthMetrics(
        taxableIncome: 0, untaxableIncome: 0, expenses: 0,
        reallocated: 0, positiveReallocation: 0, negativeReallocation: 0,
        incomeNeeded: 0, breakEven: 0, remaining: 0, taxSavings: 0
    )
}

// MARK: - Month Overview Rows View

/// Shared row content for BudgetPageView's monthly overview section and
/// per-month rows. When `yearMonth` is non-nil, rows are wrapped in tappable Buttons
/// that navigate to that month; otherwise they are plain static HStacks.
struct MonthOverviewRowsView: View {
    let m: MonthMetrics
    let item: Item
    let selectedCurrency: Currency
    let yearMonth: YearMonth?
    let navigationPath: Binding<NavigationPath>?
    var hideReallocations: Bool = false

    private var showReallocations: Bool {
        item.effectiveShowReallocationsRow && !hideReallocations
    }

    var body: some View {
        Group {
            if showReallocations {
                row("Reallocated", value: m.positiveReallocation, color: .green, id: "other-income")
            }
            if item.isTaxSavingsEnabled {
                if item.effectiveShowOtherIncomeRow {
                    row("Other Income",
                        value: showReallocations ? m.untaxableIncome : roundMoney(m.untaxableIncome + m.positiveReallocation),
                        color: .green, id: "Nontaxable-income")
                    row("Taxable Income", value: m.taxableIncome, color: .green, id: "taxable-income")
                } else {
                    row("Income",
                        value: showReallocations
                            ? roundMoney(m.taxableIncome + m.untaxableIncome)
                            : roundMoney(roundMoney(m.taxableIncome + m.untaxableIncome) + m.positiveReallocation),
                        color: .green, id: "taxable-income")
                }
            } else {
                row("Income",
                    value: showReallocations ? m.untaxableIncome : roundMoney(m.untaxableIncome + m.positiveReallocation),
                    color: .green, id: "Nontaxable-income")
            }
            if item.isTaxSavingsEnabled && item.effectiveShowTaxesGoalRow {
                row("Tax Savings", value: m.taxSavings, color: .orange, id: "tax-savings")
            }
            if item.effectiveShowExpensesRow {
                let mergedTax = item.isTaxSavingsEnabled && !item.effectiveShowTaxesGoalRow ? m.taxSavings : 0.0
                row("Expenses",
                    value: showReallocations
                        ? roundMoney(m.expenses + mergedTax)
                        : roundMoney(roundMoney(m.expenses + m.negativeReallocation) + mergedTax),
                    color: .red, id: "expenses")
            }
            if showReallocations {
                row("Reallocated", value: m.negativeReallocation, color: .red, id: "removed-from")
            }
            if item.effectiveShowIncomeSurplusRow {
                neededExcessRow()
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, value: Decimal, color: Color, id: String) -> some View {
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
                Text(label).fontWeight(.medium)
                Spacer()
                Text(value, format: .currency(code: selectedCurrency.code))
                    .foregroundStyle(color)
                    .fontWeight(.medium)
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
            neededExcessContent(medium: true)
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
                Text(Decimal(0), format: .currency(code: selectedCurrency.code))
                    .foregroundStyle(.indigo).if(medium) { $0.fontWeight(.medium) }
            } else {
                Text("Needed Income").if(medium) { $0.fontWeight(.medium) }
                Spacer()
                HStack(spacing: 4) {
                    Text(m.breakEven, format: .currency(code: selectedCurrency.code))
                        .foregroundStyle(.indigo).if(medium) { $0.fontWeight(.medium) }
                    if item.isTaxSavingsEnabled {
                        Text("/").foregroundStyle(.primary).offset(y: -1)
                        Text(m.incomeNeeded, format: .currency(code: selectedCurrency.code))
                            .foregroundStyle(.indigo).if(medium) { $0.fontWeight(.medium) }
                    }
                }
            }
        }
        .if(medium) { $0.contentShape(Rectangle()) }
    }
}
