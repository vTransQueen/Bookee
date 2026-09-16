//
//  SearchView.swift
//  Bookee
//

import SwiftUI
import SwiftData

// MARK: - Universal Search Overlay

/// Full-screen search overlay placed in a ZStack above the app content.
/// Uses a NavigationStack with .searchable for the native iOS search bar.
struct UniversalSearchOverlay: View {
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                } else {
                    SearchResultsView(searchText: searchText) {
                        dismiss()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search everything")
        .onAppear {
            searchText = NavigationStateManager.shared.universalSearchText
            isSearchPresented = true
        }
        .onChange(of: searchText) { _, newValue in
            // Only persist non-empty queries so that the Cancel button clearing the
            // searchable text doesn't wipe the saved results.
            if !newValue.isEmpty {
                NavigationStateManager.shared.universalSearchText = newValue
            }
        }
        .onChange(of: isSearchPresented) { _, presented in
            if !presented { dismiss() }
        }
    }

    private func dismiss() {
        isSearchPresented = false
        withAnimation(.easeInOut(duration: 0.2)) { NavigationStateManager.shared.showingUniversalSearch = false }
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    let searchText: String
    var onNavigate: (() -> Void)?

    /// Every Item regardless of trash state — split into active/trashed below so trashed data
    /// can still be found (and clearly marked) instead of vanishing from search entirely.
    @Query private var allItems: [Item]

    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .manual
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("maxBackupsToKeep") private var maxBackupsToKeep: Int = 5
    @AppStorage("automaticBackupsEnabled") private var automaticBackupsEnabled: Bool = true
    @HighlightColorStorage private var highlightColor

    @State private var budgetIndex: [BudgetSearchIndex] = []
    @State private var backups: [Backup] = []
    @State private var isIndexed = false

    // MARK: - Item Partitions

    private var activeItems: [Item] {
        allItems.filter { !$0.isUnsavedDuplicate && $0.deletedDate == nil }
    }

    private var trashedItems: [Item] {
        allItems.filter { !$0.isUnsavedDuplicate && $0.deletedDate != nil }
    }

    // MARK: - Filtered results

    private var matchingBudgets: [Item] {
        sortedItems(activeItems.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }, by: sortOrder)
    }

    /// Trashed budgets whose name matches. Rendered with a trash-days badge; tapping always
    /// lands on Home Trash since a trashed budget's normal page isn't the right destination.
    private var matchingTrashedBudgets: [Item] {
        sortedItems(trashedItems.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }, by: sortOrder)
    }

    /// One entry per active budget with any matching content — transactions, odometer readings,
    /// budget attachments, or per-budget settings — grouped under a single section per budget so
    /// a budget with matches across several categories doesn't repeat its header. Trashed budgets
    /// are excluded entirely: only the budget itself (in the Trash section) surfaces, not its
    /// nested items, since a trashed budget's contents aren't independently reachable.
    private var matchingGroupsByBudget: [BudgetMatchGroup] {
        budgetIndex.compactMap { entry in
            let item = entry.item
            guard !item.isDeleted else { return nil }

            let matchingExpenses = entry.expenses.filter { expenseMatches($0) }
            let matchingIncomes = entry.incomes.filter { incomeMatches($0) }
            let transactions = (matchingExpenses.map { TransactionItem.expense($0, adjustedDate: $0.date) } +
                                 matchingIncomes.map { TransactionItem.income($0, adjustedDate: $0.date) })
                .sorted {
                    if $0.sortDate != $1.sortDate { return $0.sortDate < $1.sortDate }
                    return $0.createdAt < $1.createdAt
                }

            let matchingOdometerReadings = entry.odometerReadings
                .filter { odometerReadingMatches($0) }
                .sorted { $0.date < $1.date }

            let matchingAttachments = entry.attachments
                .filter { $0.fileName.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.dateAdded < $1.dateAdded }

            let matchingBudgetSettings = budgetSettingsEntries(for: item).filter { settingEntry in
                settingEntry.searchTerms.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }

            guard !transactions.isEmpty || !matchingOdometerReadings.isEmpty || !matchingAttachments.isEmpty || !matchingBudgetSettings.isEmpty else {
                return nil
            }

            return BudgetMatchGroup(
                item: item,
                transactions: transactions,
                odometerReadings: matchingOdometerReadings,
                attachments: matchingAttachments,
                settingsEntries: matchingBudgetSettings
            )
        }
    }

    /// Settings entries rebuilt from live @AppStorage/@HighlightColorStorage values (plus loaded
    /// backups) so the trailing value text — and the list of individual backups — always match
    /// what Settings/Backups shows right now.
    private var settingsEntries: [SettingsEntry] {
        var entries: [SettingsEntry] = [
            SettingsEntry(label: "Currency", searchTerms: ["Currency"], kind: .picker(valueText: "\(selectedCurrency.symbol) \(selectedCurrency.code)"), page: .settings),
            SettingsEntry(label: "Sort Order", searchTerms: ["Sort Order"], kind: .picker(valueText: sortOrder.rawValue), page: .settings),
            SettingsEntry(label: "Date Format", searchTerms: ["Date Format"], kind: .picker(valueText: dateFormat.rawValue), page: .settings),
            SettingsEntry(label: "Tint", searchTerms: ["Tint", "Highlight Color", "Color"], kind: .colorSwatch(highlightColor), page: .settings),
            SettingsEntry(label: "Appearance", searchTerms: ["Appearance"], kind: .picker(valueText: appearanceMode.rawValue), page: .settings),
            SettingsEntry(label: "Backups", searchTerms: ["Backups"], kind: .navigationLink, page: .backups),
            SettingsEntry(label: "Home Trash", searchTerms: ["Home Trash", "Trash"], kind: .navigationLink, page: .trash),
            SettingsEntry(label: "Keep Backups", searchTerms: ["Keep Backups"], kind: .picker(valueText: "\(maxBackupsToKeep)"), page: .backups),
            SettingsEntry(label: "Automatic Backups", searchTerms: ["Automatic Backups"], kind: .picker(valueText: automaticBackupsEnabled ? "On" : "Off"), page: .backups),
        ]
        entries += backups.map { backup in
            SettingsEntry(label: backup.displayName, searchTerms: [backup.displayName], kind: .navigationLink, page: .backups)
        }
        return entries
    }

    private var matchingSettings: [SettingsEntry] {
        settingsEntries.filter { entry in
            entry.searchTerms.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var hasResults: Bool {
        !matchingBudgets.isEmpty || !matchingTrashedBudgets.isEmpty || !matchingGroupsByBudget.isEmpty || !matchingSettings.isEmpty
    }

    // MARK: - Body

    var body: some View {
        List {
            if !hasResults {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                if !matchingBudgets.isEmpty {
                    Section {
                        ForEach(matchingBudgets) { item in
                            Button {
                                navigate { NavigationStateManager.shared.navigateToItem(item) }
                            } label: {
                                BudgetItemRowContent(item: item, dateFormat: dateFormat, sortOrder: sortOrder)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Budgets")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }

                if !matchingTrashedBudgets.isEmpty {
                    Section {
                        ForEach(matchingTrashedBudgets) { item in
                            Button {
                                navigate { NavigationStateManager.shared.navigate(to: .trash) }
                            } label: {
                                BudgetItemRowContent(
                                    item: item,
                                    dateFormat: dateFormat,
                                    sortOrder: sortOrder,
                                    nameOverride: item.trashDisplayName,
                                    showsChevron: false,
                                    trashDaysLeft: item.daysUntilPermanentDeletion
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Trash")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }

                ForEach(matchingGroupsByBudget, id: \.item.persistentModelID) { group in
                    Section {
                        ForEach(group.transactions) { transaction in
                            transactionRow(transaction, in: group.item)
                        }
                        ForEach(group.odometerReadings) { reading in
                            odometerRow(reading, in: group.item)
                        }
                        ForEach(group.attachments) { attachment in
                            budgetAttachmentRow(attachment, in: group.item)
                        }
                        ForEach(group.settingsEntries) { entry in
                            budgetSettingsRow(entry, for: group.item)
                        }
                    } header: {
                        Text(group.item.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }

                if !matchingSettings.isEmpty {
                    Section {
                        ForEach(matchingSettings) { entry in
                            settingsRow(entry)
                        }
                    } header: {
                        Text("Settings")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            guard !isIndexed else { return }
            var index: [BudgetSearchIndex] = []
            for item in allItems where !item.isUnsavedDuplicate && !item.isDeleted {
                guard let data = item.decodeBudgetData() else { continue }
                index.append(BudgetSearchIndex(
                    item: item,
                    expenses: data.expenses,
                    incomes: data.incomes,
                    attachments: data.attachments,
                    odometerReadings: data.odometerReadings
                ))
            }
            budgetIndex = index
            backups = BackupManager.shared.loadBackups()
            isIndexed = true
        }
    }

    // MARK: - Match Predicates

    /// Matches on the expense's own name, any of its categories, or any attachment filename —
    /// so searching a category or receipt filename surfaces the expense it belongs to.
    private func expenseMatches(_ expense: Expense) -> Bool {
        expense.name.localizedCaseInsensitiveContains(searchText)
            || expense.categories.contains { $0.localizedCaseInsensitiveContains(searchText) }
            || expense.attachments.contains { $0.fileName.localizedCaseInsensitiveContains(searchText) }
    }

    /// Matches on the income's own name, any of its categories, or any attachment filename.
    private func incomeMatches(_ income: Income) -> Bool {
        income.name.localizedCaseInsensitiveContains(searchText)
            || income.categories.contains { $0.localizedCaseInsensitiveContains(searchText) }
            || income.attachments.contains { $0.fileName.localizedCaseInsensitiveContains(searchText) }
    }

    /// Matches on the reading's vehicle name or any of its categories.
    private func odometerReadingMatches(_ reading: OdometerReading) -> Bool {
        reading.vehicle.localizedCaseInsensitiveContains(searchText)
            || reading.categories.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// Per-budget settings entries mirroring BudgetDetailsView's "Taxes" and "Week Starts On"
    /// rows, so those become searchable the same way global Settings rows are.
    private func budgetSettingsEntries(for item: Item) -> [BudgetSettingsEntry] {
        let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let weekStartName = weekdayNames[item.effectiveCalendarWeekStartDay - 1]
        return [
            BudgetSettingsEntry(
                label: "Taxes",
                searchTerms: ["Taxes", "Tax Savings", "Percentage"],
                valueText: item.isTaxSavingsEnabled ? "\(PercentageFormatter.formatForTextField(item.taxSavingsPercentage))%" : "Off"
            ),
            BudgetSettingsEntry(
                label: "Week Starts On",
                searchTerms: ["Week Starts On"],
                valueText: weekStartName
            ),
        ]
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func transactionRow(_ transaction: TransactionItem, in item: Item) -> some View {
        switch transaction {
        case .expense(let expense, let adjustedDate):
            let isEntryTrashed = expense.deletedDate != nil
            Button {
                navigateToOccurrence(date: expense.date, item: item, scrollID: "\(expense.id.uuidString)-\(expense.date.timeIntervalSince1970)", isEntryTrashed: isEntryTrashed)
            } label: {
                HighlightableExpenseRow(expense: expense, displayDate: adjustedDate, dateFormat: dateFormat, selectedCurrency: selectedCurrency, trashDaysLeft: isEntryTrashed ? expense.daysUntilTrashDeletion : nil)
            }
            .buttonStyle(.plain)
        case .income(let income, _):
            let isEntryTrashed = income.deletedDate != nil
            Button {
                navigateToOccurrence(date: income.date, item: item, scrollID: "\(income.id.uuidString)-\(income.date.timeIntervalSince1970)", isEntryTrashed: isEntryTrashed)
            } label: {
                IncomeRowContent(
                    income: income,
                    dateFormat: dateFormat,
                    selectedCurrency: selectedCurrency,
                    taxSavingsPercentage: item.taxSavingsPercentage,
                    isTaxSavingsEnabled: item.isTaxSavingsEnabled,
                    distributedTaxAmount: nil,
                    trashDaysLeft: isEntryTrashed ? income.daysUntilTrashDeletion : nil
                )
            }
            .buttonStyle(.plain)
        case .reallocation:
            EmptyView()
        }
    }

    @ViewBuilder
    private func odometerRow(_ reading: OdometerReading, in item: Item) -> some View {
        Button {
            navigateToOdometerReading(reading, item: item)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.vehicle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    Text(reading.date, format: dateFormat.style)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Text("\(reading.odometerValue) mi")
                    .foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func budgetAttachmentRow(_ attachment: BudgetAttachment, in item: Item) -> some View {
        let isEntryTrashed = attachment.deletedDate != nil
        Button {
            navigateToBudgetAttachment(attachment, item: item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileNameWithoutExtension(attachment.fileName))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    if isEntryTrashed, let daysLeft = attachment.daysUntilTrashDeletion {
                        Text(daysLeft > 0 ? "\(daysLeft) Day\(daysLeft == 1 ? "" : "s")" : "Today")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Image(systemName: attachment.fileType.icon)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func budgetSettingsRow(_ entry: BudgetSettingsEntry, for item: Item) -> some View {
        Button {
            navigateToBudgetSettingsEntry(item)
        } label: {
            HStack {
                Text(entry.label)
                Spacer()
                Text(entry.valueText)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    /// Mirrors the row's real appearance in Settings/Backups: a picker shows its current value,
    /// the tint row shows a swatch, and Backups/Home Trash show a plain disclosure chevron like
    /// their real `NavigationLink`s. Tapping always navigates to the owning page, same as before.
    @ViewBuilder
    private func settingsRow(_ entry: SettingsEntry) -> some View {
        Button {
            navigate { NavigationStateManager.shared.navigate(to: entry.page) }
        } label: {
            HStack {
                Text(entry.label)
                Spacer()
                switch entry.kind {
                case .picker(let valueText):
                    Text(valueText)
                        .foregroundStyle(.secondary)
                case .colorSwatch(let color):
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                case .navigationLink:
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Navigation Helpers

    /// Navigates to a specific expense/income occurrence. An individually-trashed entry (inside
    /// an active budget) routes to that budget's own trash; otherwise this jumps straight to the
    /// occurrence's month and scrolls to it.
    private func navigateToOccurrence(date: Date, item: Item, scrollID: String, isEntryTrashed: Bool) {
        if isEntryTrashed {
            navigate { NavigationStateManager.shared.navigateToBudgetTrash(item) }
        } else {
            let cal = Calendar.current
            let ym = YearMonth(year: cal.component(.year, from: date), month: cal.component(.month, from: date))
            NavigationStateManager.shared.pendingScrollTarget = PendingScrollTarget(
                itemTimestamp: item.timestamp,
                yearMonth: ym,
                scrollID: scrollID
            )
            navigate { NavigationStateManager.shared.navigateToItem(item) }
        }
    }

    /// Odometer readings have no individual trash state.
    private func navigateToOdometerReading(_ reading: OdometerReading, item: Item) {
        let cal = Calendar.current
        let ym = YearMonth(year: cal.component(.year, from: reading.date), month: cal.component(.month, from: reading.date))
        NavigationStateManager.shared.pendingScrollTarget = PendingScrollTarget(
            itemTimestamp: item.timestamp,
            yearMonth: ym,
            scrollID: reading.id.uuidString
        )
        navigate { NavigationStateManager.shared.navigateToItem(item) }
    }

    private func navigateToBudgetAttachment(_ attachment: BudgetAttachment, item: Item) {
        if attachment.deletedDate != nil {
            navigate { NavigationStateManager.shared.navigateToBudgetTrash(item) }
        } else {
            let ym = YearMonth(year: attachment.year, month: attachment.month)
            NavigationStateManager.shared.pendingScrollTarget = PendingScrollTarget(
                itemTimestamp: item.timestamp,
                yearMonth: ym,
                scrollID: attachment.id.uuidString
            )
            navigate { NavigationStateManager.shared.navigateToItem(item) }
        }
    }

    /// Opens the budget's page then flags its Budget Details sheet to present once mounted.
    private func navigateToBudgetSettingsEntry(_ item: Item) {
        NavigationStateManager.shared.pendingBudgetDetailsTimestamp = item.timestamp
        navigate { NavigationStateManager.shared.navigateToItem(item) }
    }

    private func navigate(_ action: @escaping () -> Void) {
        onNavigate?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            action()
        }
    }
}

// MARK: - Budget Search Index

/// Per-budget slice of the search index, built only for active (non-trashed) budgets: every
/// expense/income/attachment/odometer reading — including individually-trashed ones nested
/// inside an active budget, so those stay findable — decoded once up front so filtering as the
/// user types doesn't re-decode on every keystroke.
private struct BudgetSearchIndex {
    let item: Item
    let expenses: [Expense]
    let incomes: [Income]
    let attachments: [BudgetAttachment]
    let odometerReadings: [OdometerReading]
}

// MARK: - Budget Match Group

/// All matching content for a single budget, grouped so the search results list shows one
/// section per budget instead of repeating its header per matched category.
private struct BudgetMatchGroup {
    let item: Item
    let transactions: [TransactionItem]
    let odometerReadings: [OdometerReading]
    let attachments: [BudgetAttachment]
    let settingsEntries: [BudgetSettingsEntry]
}

// MARK: - Settings Entry

/// What the trailing side of a settings search row shows, matching that row's real control:
/// a Picker's current value, the tint ColorPicker's swatch, or a NavigationLink's chevron.
private enum SettingsRowKind {
    case picker(valueText: String)
    case colorSwatch(Color)
    case navigationLink
}

private struct SettingsEntry: Identifiable {
    let id = UUID()
    /// Displayed text — kept identical to the real control's label (e.g. "Tint", not
    /// "Highlight Color") so the row reads the same as it does in Settings.
    let label: String
    /// Extra words the search should match against beyond `label` (e.g. "Highlight Color" for
    /// the "Tint" row), since a user searching won't necessarily know the on-screen label.
    let searchTerms: [String]
    let kind: SettingsRowKind
    let page: AppPage
}

// MARK: - Budget Settings Entry

/// Per-budget counterpart to `SettingsEntry` for rows that live in BudgetDetailsView (Taxes,
/// Week Starts On) rather than the global Settings page. Navigation always opens that specific
/// budget's Budget Details sheet, so this carries a plain value/label pair rather than an
/// `AppPage`.
private struct BudgetSettingsEntry: Identifiable {
    let id = UUID()
    let label: String
    let searchTerms: [String]
    let valueText: String
}
