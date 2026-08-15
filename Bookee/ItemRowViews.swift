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
    let isSelecting: Bool
    let isReordering: Bool
    let isSelected: Bool
    let dateFormat: DateFormat
    let selectedCurrency: Currency
    let highlightColor: Color
    let taxSavingsPercentage: Double
    let isTaxSavingsEnabled: Bool
    let distributedTaxAmount: Double? // Pre-calculated distributed tax amount from TaxDistributionHelper
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHighlighted = false

    /// The tax savings amount to display for this income.
    /// Uses the pre-calculated distributed amount if available (ensuring totals match),
    /// otherwise falls back to calculating individually (which may cause rounding discrepancies).
    private var taxSavingsAmount: Double {
        // Use distributed amount if provided, otherwise fall back to individual calculation
        if let distributedAmount = distributedTaxAmount {
            return distributedAmount.roundedMoney()
        }
        // Fallback: calculate individually. Rate must NOT be rounded to 2dp —
        // that would corrupt values like 11.5% → 0.11.
        return income.amount.taxAmount(rate: taxSavingsPercentage / 100.0)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Show selection indicator on the left when in selection mode
            if isSelecting {
                selectionIndicator
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(income.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(isHighlighted ? highlightColor : .primary)
                    incomeMetadataView
                }
                Spacer()
                amountView
            }
            .animation(nil, value: isSelecting) // Prevent unwanted animations when toggling selection mode
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        // Only show context menu in normal mode (not during selection or reordering)
        .if(!isSelecting && !isReordering) { view in
            view
                .contextMenu {
                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.primary)

                    Divider()

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(action: onDuplicate) {
                        Image(systemName: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
        }
        .animation(.default, value: isHighlighted)
        .onReceive(NotificationCenter.default.publisher(for: .highlightNewItem)) { notification in
            guard let id = notification.object as? UUID, id == income.id else { return }
            isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isHighlighted = false
            }
        }
    }

    /// Selection indicator showing either a filled checkmark (selected) or empty circle (unselected)
    private var selectionIndicator: some View {
        SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
            .transition(.move(edge: .leading).combined(with: .opacity))
            .padding(.trailing, 12)
    }

    /// Amount display with optional tax savings or nontaxable indicator
    private var amountView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(income.amount, format: .currency(code: selectedCurrency.code))
                .foregroundStyle(isHighlighted ? highlightColor : .green)

            // Show either nontaxable indicator or tax savings
            if !income.isTaxable {
                Text("Nontaxable")
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? highlightColor : .secondary)
            } else if isTaxSavingsEnabled && taxSavingsPercentage.isEffectivelyPositive {
                HStack(spacing: 4) {
                    Text("Taxes")
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                    Text(taxSavingsAmount, format: .currency(code: selectedCurrency.code))
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                }
            }
        }
    }

    /// Metadata display showing date, recurring frequency (if applicable), and attachment count (if any)
    @ViewBuilder
    private var incomeMetadataView: some View {
        HStack(spacing: 4) {
            // Always display the date
            Text(income.date, format: dateFormat.style)
                .font(.caption)
                .foregroundStyle(isHighlighted ? highlightColor : .secondary)

            // Show recurring frequency if applicable
            if income.isRecurring {
                Text("• \(income.recurringFrequency.rawValue)")
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? highlightColor : .secondary)
            }

            // Show attachment indicator if attachments exist
            if !income.attachments.isEmpty {
                attachmentIndicator
            }
        }
    }

    /// Attachment count indicator showing a paperclip icon and count
    private var attachmentIndicator: some View {
        Group {
            // Bullet separator (date is always shown, so separator is always needed)
            Text("•")
                .font(.caption)
                .foregroundStyle(isHighlighted ? highlightColor : .secondary)

            HStack(spacing: 2) {
                Image(systemName: "paperclip")
                    .font(.caption2)
                    .foregroundStyle(isHighlighted ? highlightColor : .secondary)
                Text("\(income.attachments.count)")
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? highlightColor : .secondary)
            }
        }
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
