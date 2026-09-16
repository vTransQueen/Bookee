//
//  BudgetTrashView.swift
//  Bookee
//
//  Pushed via NavigationLink from BudgetDetailsView. Loads soft-deleted
//  expenses, incomes, and attachments from the item, lets the user restore
//  or permanently delete them, and saves changes back to the item directly.
//  Items are kept for 30 days then auto-purged on next budget load.
//

import SwiftUI
import SwiftData

struct BudgetTrashView: View {
    var item: Item
    var dismissSheet: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @HighlightColorStorage private var highlightColor

    @State private var expenses: [Expense] = []
    @State private var incomes: [Income] = []
    @State private var attachments: [BudgetAttachment] = []
    @State private var reallocations: [Reallocation] = []
    @State private var odometerReadings: [OdometerReading] = []

    @State private var isSelecting = false
    @State private var selectedExpenseIDs = Set<UUID>()
    @State private var selectedIncomeIDs = Set<UUID>()
    @State private var selectedAttachmentIDs = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var deleteAction: DeleteAction = .emptyTrash

    // MARK: - Delete Action

    private enum DeleteAction {
        case emptyTrash
        case singleExpense(Expense)
        case singleIncome(Income)
        case singleAttachment(BudgetAttachment)
        case selectedItems

        var title: String {
            switch self {
            case .emptyTrash: return "Empty Trash?"
            case .singleExpense, .singleIncome, .singleAttachment: return "Delete Item?"
            case .selectedItems: return "Delete Selected Items?"
            }
        }

        func message(totalCount: Int, selectedCount: Int) -> String {
            switch self {
            case .emptyTrash:
                return "This will permanently delete all \(totalCount) item\(totalCount == 1 ? "" : "s") in the trash. This action cannot be undone."
            case .singleExpense(let expense):
                return "This will permanently delete '\(expense.name.isEmpty ? "Expense" : expense.name)'. This action cannot be undone."
            case .singleIncome(let income):
                return "This will permanently delete '\(income.name.isEmpty ? "Income" : income.name)'. This action cannot be undone."
            case .singleAttachment(let attachment):
                return "This will permanently delete '\(fileNameWithoutExtension(attachment.fileName))'. This action cannot be undone."
            case .selectedItems:
                return "This will permanently delete \(selectedCount) item\(selectedCount == 1 ? "" : "s"). This action cannot be undone."
            }
        }

        var buttonTitle: String {
            switch self {
            case .emptyTrash: return "Empty Trash"
            case .singleExpense, .singleIncome, .singleAttachment, .selectedItems: return "Delete"
            }
        }
    }

    // MARK: - Derived

    private var deletedExpenses: [Expense] {
        expenses.filter { $0.deletedDate != nil }
            .sorted { ($0.deletedDate ?? .distantPast) > ($1.deletedDate ?? .distantPast) }
    }

    private var deletedIncomes: [Income] {
        incomes.filter { $0.deletedDate != nil }
            .sorted { ($0.deletedDate ?? .distantPast) > ($1.deletedDate ?? .distantPast) }
    }

    private var deletedAttachments: [BudgetAttachment] {
        attachments.filter { $0.deletedDate != nil }
            .sorted { ($0.deletedDate ?? .distantPast) > ($1.deletedDate ?? .distantPast) }
    }

    private var totalDeletedCount: Int { deletedExpenses.count + deletedIncomes.count + deletedAttachments.count }
    private var totalSelectedCount: Int { selectedExpenseIDs.count + selectedIncomeIDs.count + selectedAttachmentIDs.count }
    private var allSelected: Bool { totalSelectedCount == totalDeletedCount && totalDeletedCount > 0 }
    private var isEmpty: Bool { totalDeletedCount == 0 }

    // MARK: - Body

    var body: some View {
        ZStack {
            List {
                if !deletedExpenses.isEmpty {
                    Section {
                        ForEach(deletedExpenses) { expense in
                            expenseRow(expense)
                        }
                    }
                }
                if !deletedIncomes.isEmpty {
                    Section {
                        ForEach(deletedIncomes) { income in
                            incomeRow(income)
                        }
                    }
                }
                if !deletedAttachments.isEmpty {
                    Section {
                        ForEach(deletedAttachments) { attachment in
                            attachmentRow(attachment)
                        }
                    }
                }

            }
            .listStyle(.insetGrouped)
            .animation(.easeInOut(duration: 0.2), value: isSelecting)

            if isEmpty {
                EmptyStatePlaceholder(
                    systemImage: "trash",
                    title: "Trash is Empty",
                    message: "Deleted expenses, income, and attachments will appear here and be kept for 30 days"
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismissSheet?() ?? dismiss()
                } label: {
                    Label("Budget Trash", systemImage: "trash")
                        .labelStyle(.titleOnly)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { NavigationStateManager.shared.showingUniversalSearch = true } } label: {
                    Image(systemName: "magnifyingglass")
                }
                .tint(.primary)
            }
            bottomToolbarItem
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert(deleteAction.title, isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button(deleteAction.buttonTitle, role: .destructive) {
                            performDelete()
                        }
                    } message: {
                        Text(deleteAction.message(totalCount: totalDeletedCount, selectedCount: totalSelectedCount))
                    }
            }
        }
        .onAppear { loadData() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var bottomToolbarItem: some ToolbarContent {
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation { isSelecting = false }
                    selectedExpenseIDs.removeAll()
                    selectedIncomeIDs.removeAll()
                    selectedAttachmentIDs.removeAll()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.primary)

                Button {
                    restoreSelectedItems()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(.primary)
                .disabled(totalSelectedCount == 0)

                Spacer()

                let selectAllText = allSelected ? "Deselect All" : "Select All"
                Button {
                    guard !isEmpty else { return }
                    if allSelected {
                        selectedExpenseIDs.removeAll()
                        selectedIncomeIDs.removeAll()
                        selectedAttachmentIDs.removeAll()
                    } else {
                        selectedExpenseIDs = Set(deletedExpenses.map(\.id))
                        selectedIncomeIDs = Set(deletedIncomes.map(\.id))
                        selectedAttachmentIDs = Set(deletedAttachments.map(\.id))
                    }
                } label: {
                    Label(selectAllText, systemImage: allSelected ? "checklist.unchecked" : "checklist.checked")
                }
                .tint(.primary)

                Button(role: .destructive) {
                    guard totalSelectedCount > 0 else { return }
                    deleteAction = .selectedItems
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        } else {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation { isSelecting = true }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .tint(.primary)
                .disabled(isEmpty)

                Spacer()

                Button(role: .destructive) {
                    guard !isEmpty else { return }
                    deleteAction = .emptyTrash
                    showingDeleteConfirmation = true
                } label: {
                    Label("Empty Trash", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: selectedExpenseIDs.contains(expense.id), highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }
            HighlightableExpenseRow(
                expense: expense,
                displayDate: expense.date,
                dateFormat: dateFormat,
                selectedCurrency: selectedCurrency,
                trashDaysLeft: expense.daysUntilTrashDeletion
            )
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { selectedExpenseIDs.toggle(expense.id) }
        }
        .contextMenu {
            Button { restoreExpense(expense) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.primary)
            Divider()
            Button(role: .destructive) {
                deleteAction = .singleExpense(expense)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    deleteAction = .singleExpense(expense)
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isSelecting {
                Button { restoreExpense(expense) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func incomeRow(_ income: Income) -> some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: selectedIncomeIDs.contains(income.id), highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }
            IncomeRowContent(
                income: income,
                dateFormat: dateFormat,
                selectedCurrency: selectedCurrency,
                taxSavingsPercentage: item.taxSavingsPercentage,
                isTaxSavingsEnabled: item.isTaxSavingsEnabled,
                distributedTaxAmount: nil,
                trashDaysLeft: income.daysUntilTrashDeletion
            )
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { selectedIncomeIDs.toggle(income.id) }
        }
        .contextMenu {
            Button { restoreIncome(income) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.primary)
            Divider()
            Button(role: .destructive) {
                deleteAction = .singleIncome(income)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    deleteAction = .singleIncome(income)
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isSelecting {
                Button { restoreIncome(income) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: BudgetAttachment) -> some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: selectedAttachmentIDs.contains(attachment.id), highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fileNameWithoutExtension(attachment.fileName))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                if let daysLeft = attachment.daysUntilTrashDeletion {
                    Text(daysLeft > 0 ? "\(daysLeft) Day\(daysLeft == 1 ? "" : "s")" : "Today")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { selectedAttachmentIDs.toggle(attachment.id) }
        }
        .contextMenu {
            Button { restoreAttachment(attachment) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.primary)
            Divider()
            Button(role: .destructive) {
                deleteAction = .singleAttachment(attachment)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    deleteAction = .singleAttachment(attachment)
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isSelecting {
                Button { restoreAttachment(attachment) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let data = item.decodeBudgetData() else { return }
        expenses = data.expenses
        incomes = data.incomes
        attachments = data.attachments
        reallocations = data.reallocations
        odometerReadings = data.odometerReadings
    }

    private func persist() {
        try? item.encodeBudgetData(
            expenses: expenses,
            incomes: incomes,
            attachments: attachments,
            reallocations: reallocations,
            odometerReadings: odometerReadings
        )
        modelContext.saveWithLogging("BudgetTrashView: persist")
    }

    // MARK: - Actions

    private func performDelete() {
        switch deleteAction {
        case .emptyTrash:
            emptyTrash()
        case .singleExpense(let expense):
            expenses.removeAll { $0.id == expense.id }
            persist()
        case .singleIncome(let income):
            incomes.removeAll { $0.id == income.id }
            persist()
        case .singleAttachment(let attachment):
            attachments.removeAll { $0.id == attachment.id }
            persist()
        case .selectedItems:
            permanentlyDeleteSelectedItems()
        }
    }

    private func restoreExpense(_ expense: Expense) {
        guard let idx = expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        expenses[idx].deletedDate = nil
        persist()
    }

    private func restoreIncome(_ income: Income) {
        guard let idx = incomes.firstIndex(where: { $0.id == income.id }) else { return }
        incomes[idx].deletedDate = nil
        persist()
    }

    private func restoreAttachment(_ attachment: BudgetAttachment) {
        guard let idx = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        attachments[idx].deletedDate = nil
        persist()
    }

    private func restoreSelectedItems() {
        for i in expenses.indices where selectedExpenseIDs.contains(expenses[i].id) {
            expenses[i].deletedDate = nil
        }
        for i in incomes.indices where selectedIncomeIDs.contains(incomes[i].id) {
            incomes[i].deletedDate = nil
        }
        for i in attachments.indices where selectedAttachmentIDs.contains(attachments[i].id) {
            attachments[i].deletedDate = nil
        }
        selectedExpenseIDs.removeAll()
        selectedIncomeIDs.removeAll()
        selectedAttachmentIDs.removeAll()
        isSelecting = false
        persist()
    }

    private func permanentlyDeleteSelectedItems() {
        expenses.removeAll { selectedExpenseIDs.contains($0.id) }
        incomes.removeAll { selectedIncomeIDs.contains($0.id) }
        attachments.removeAll { selectedAttachmentIDs.contains($0.id) }
        selectedExpenseIDs.removeAll()
        selectedIncomeIDs.removeAll()
        selectedAttachmentIDs.removeAll()
        isSelecting = false
        persist()
    }

    private func emptyTrash() {
        expenses.removeAll { $0.deletedDate != nil }
        incomes.removeAll { $0.deletedDate != nil }
        attachments.removeAll { $0.deletedDate != nil }
        persist()
    }
}
