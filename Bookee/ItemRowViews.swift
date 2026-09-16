//
//  ItemRowViews.swift
//  Bookee
//
//  Reusable row views for displaying items in lists.
//

import SwiftUI

// MARK: - Selection Indicator

/// Reusable checkmark/circle indicator for list rows in selection mode.
/// Callers add their own trailing padding and any transitions.
struct SelectionIndicator: View {
    let isSelected: Bool
    var highlightColor: Color = .blue

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? highlightColor : .gray)
            .imageScale(.large)
    }
}

// MARK: - Budget Item Row Content

/// Content-only row for a top-level budget/income `Item`, shared by the home list, home Trash,
/// and Search so the same record looks identical everywhere. Carries no tap/selection/context-menu
/// behavior — callers own that, since Trash and Search don't drive the row the same way the home
/// list does.
struct BudgetItemRowContent: View {
    let item: Item
    let dateFormat: DateFormat
    let sortOrder: SortOrder
    var nameOverride: String? = nil
    var showsChevron: Bool = true
    /// Days left before permanent deletion; rendered as a red "• N Days" suffix. Trash-only.
    var trashDaysLeft: Int? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(nameOverride ?? item.displayName)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(sortOrder == .dateAdded ?
                         "Date added: \(item.timestamp, format: dateFormat.styleWithTime)" :
                         "Last updated: \(item.lastModifiedDate, format: dateFormat.styleWithTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let trashDaysLeft {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(trashDaysLeft > 0 ? "\(trashDaysLeft) Day\(trashDaysLeft == 1 ? "" : "s")" : "Today")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Income Row Content

/// Content-only row for an `Income`, shared by the month list, Budget Trash, and Search.
/// Never computes a tax amount itself — `distributedTaxAmount` must be the canonical
/// largest-remainder value from `TaxDistributionHelper` (as used by the month page). When `nil`,
/// no "Taxes" caption is shown at all, since there is no month context to derive one from.
struct IncomeRowContent: View {
    let income: Income
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let taxSavingsPercentage: Double
    let isTaxSavingsEnabled: Bool
    let distributedTaxAmount: Decimal? // Pre-calculated distributed tax amount from TaxDistributionHelper
    /// Days left before permanent deletion; rendered as a red "• N Days" suffix. Trash-only.
    var trashDaysLeft: Int? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(income.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                metadataRow()
            }
            Spacer()
            amountRow()
        }
    }

    @ViewBuilder
    private func amountRow() -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(income.amount, format: .currency(code: selectedCurrency.code))
                .foregroundStyle(.green)
            if !income.isTaxable {
                Text("Nontaxable")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            } else if let distributedTaxAmount, isTaxSavingsEnabled && taxSavingsPercentage.isEffectivelyPositive {
                HStack(spacing: 4) {
                    Text("Taxes")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Text(distributedTaxAmount.roundedMoney(), format: .currency(code: selectedCurrency.code))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataRow() -> some View {
        HStack(spacing: 4) {
            Text(income.date, format: dateFormat.style)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            if income.isRecurring {
                Text("• \(income.recurringFrequency.rawValue)")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            if !income.attachments.isEmpty {
                Text("•")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                HStack(spacing: 2) {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                    Text("\(income.attachments.count)")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            if let trashDaysLeft {
                Text("•")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Text(trashDaysLeft > 0 ? "\(trashDaysLeft) Day\(trashDaysLeft == 1 ? "" : "s")" : "Today")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Income Row View

/// A reusable row view for displaying an income item with support for selection, reordering, and contextual actions.
///
/// This view displays:
/// - Income name and amount
/// - Date and optional recurring frequency
/// - Attachment count indicator (if attachments exist)
/// - Tax savings information (when enabled and applicable)
/// - Selection indicator (in selection mode)
///
/// Supports three interaction modes:
/// - Normal: Tap to edit, long press for context menu (duplicate/delete)
/// - Selection: Tap toggles selection, no context menu
/// - Reordering: No tap interaction, no context menu
struct IncomeRowView: View {
    let income: Income
    let isReordering: Bool
    let isSelected: Bool
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let highlightColor: Color
    let taxSavingsPercentage: Double
    let isTaxSavingsEnabled: Bool
    let distributedTaxAmount: Decimal? // Pre-calculated distributed tax amount from TaxDistributionHelper
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(\.selectionMode) private var selectionMode
    private var isSelecting: Bool { selectionMode.isSelecting }

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                selectionIndicator
            }
            IncomeRowContent(
                income: income,
                dateFormat: dateFormat,
                selectedCurrency: selectedCurrency,
                taxSavingsPercentage: taxSavingsPercentage,
                isTaxSavingsEnabled: isTaxSavingsEnabled,
                distributedTaxAmount: distributedTaxAmount
            )
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .contextMenu {
            if !isSelecting && !isReordering {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(.primary)

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Move to Trash", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
            .transition(.move(edge: .leading).combined(with: .opacity))
            .padding(.trailing, 12)
    }

    /// Handles tap gestures based on the current mode
    /// - Selection mode: toggles selection
    /// - Reordering mode: no action
    /// - Normal mode: opens edit sheet
    private func handleTap() {
        if isSelecting {
            onToggleSelection()
        } else if !isReordering {
            onEdit()
        }
    }
}
