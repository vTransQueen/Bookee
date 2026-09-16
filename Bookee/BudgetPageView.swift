//
//  BudgetPageView.swift
//  Bookee
//
//  Carousel host for a single budget item. Loads all budget data once and shows each
//  month's details (calendar + transactions + attachments) in a horizontal, swipeable
//  carousel of MonthPageView pages. Owns the toolbar, sheets, filter/selection state,
//  and all data mutation/persistence so pages stay lightweight and swiping is seamless.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Budget Page View (Month Carousel Host)

/// Detail view for a budget/income item. Presents each month's details in a horizontal
/// carousel; swipe left/right to move between months with no reload.
struct BudgetPageView: View {
    @Bindable var item: Item

    // MARK: Shared data (loaded once)
    @State private var expenses: [Expense] = []
    @State private var incomes: [Income] = []
    @State private var attachments: [BudgetAttachment] = []
    @State private var reallocations: [Reallocation] = []
    @State private var odometerReadings: [OdometerReading] = []
    @State private var isInitialLoad = true

    // MARK: Carousel state
    @State private var focusedYearMonth: YearMonth = YearMonth(year: Date().year, month: Date().month)
    @State private var didInitialAppear = false
    @State private var isJumpAnimating = false
    @State private var isCarouselAnimating = false
    @State private var carouselDriver = CarouselJumpDriver()
    @State private var scrollToCalendarYM: YearMonth? = nil

    // MARK: Pre-computed month data cache
    /// Incremented whenever data changes; triggers the background cache-rebuild task.
    @State private var dataVersion: Int = 0
    /// Incremented when selection or filter display state changes. Because @Binding comparisons
    /// always read the same live @State value on both sides, MonthPageView.Equatable uses this
    /// counter rather than comparing binding values to detect when pages need to re-render.
    @State private var renderVersion: Int = 0
    /// Expanded income/expense arrays per month, built off the main thread.
    /// Passed into each MonthPageView so its body never runs day-scan loops during swipes.
    @State private var monthDataCache: [YearMonth: MonthExpandedData] = [:]

    // MARK: Calendar day selection (per-month)
    @State private var selectedDaysByMonth: [YearMonth: Set<Int>] = [:]

    // MARK: Shared filter / selection
    @State private var selectedTransactionTypes: Set<TransactionFilter> = .defaultSelection
    @State private var selectedTransactionCategories: Set<String> = []
    @State private var selectedVehicleFilter: String? = nil
    /// Reference type so `.environment(\.selectionMode, selectionMode)` never changes value
    /// across re-renders — see EnvironmentValues.selectionMode for why that matters.
    @State private var selectionMode = SelectionModeModel()
    @State private var selectedExpenses = Set<OccurrenceKey>()
    @State private var selectedIncomes = Set<OccurrenceKey>()
    @State private var selectedReallocations = Set<UUID>()
    @State private var selectedAttachments = Set<UUID>()

    // MARK: Toolbar-triggered sheets
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingReallocateFunds = false
    @State private var showingAddOdometerReading = false
    @State private var showingIncomeView = false
    @State private var showingFilterAndTypeSheet = false
    @State private var showingEditDetails = false
    @State private var showingBudgetPhotoPicker = false
    @State private var showingBudgetFilePicker = false

    // MARK: Subpage restoration targets, consumed by the child page they're passed into.
    // The draft-shaped ones are shared between a form's Add and Edit variants (e.g.
    // restoreExpenseDraft feeds both AddExpenseView and EditExpenseView) since only one of
    // those can ever be open at a time.
    @State private var restoreBudgetDetailsTrash = false
    @State private var restoreBudgetDetailsDraft: BudgetDetailsDraft?
    @State private var restoreIncomeAttachmentID: UUID? = nil
    @State private var restoreExpenseDraft: TransactionFormDraft?
    @State private var restoreIncomeDraft: TransactionFormDraft?
    @State private var restoreReallocationDraft: ReallocationFormDraft?
    @State private var restoreOdometerDraft: OdometerReadingFormDraft?

    // MARK: Row-triggered sheets / edit targets
    @State private var expenseToEdit: Expense?
    @State private var incomeToEdit: Income?
    @State private var reallocationToEdit: Reallocation?
    @State private var odometerReadingToEdit: OdometerReading?
    @State private var attachmentToView: BudgetAttachment?
    @State private var expenseOccurrenceDate: Date?
    @State private var incomeOccurrenceDate: Date?

    // MARK: Delete / duplicate state
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var expenseToDelete: Expense?
    @State private var incomeToDelete: Income?
    @State private var reallocationToDelete: Reallocation?
    @State private var odometerReadingToDelete: OdometerReading?
    @State private var showingRecurringScopeAlert = false
    @State private var pendingRecurringScope: RecurringScope?
    @State private var showingRecurringDuplicateScopeAlert = false
    @State private var expenseToDuplicate: Expense?
    @State private var incomeToDuplicate: Income?
    @State private var expenseAdjustedDate: Date?
    @State private var incomeAdjustedDate: Date?

    // MARK: Add-item scroll tracking
    @State private var expenseCountBeforeAdd = 0
    @State private var incomeCountBeforeAdd = 0
    @State private var reallocationCountBeforeAdd = 0
    @State private var odometerReadingCountBeforeAdd = 0
    @State private var attachmentCountBeforeAdd = 0
    /// Scroll ID to deliver after the next cache update (renderVersion bump).
    /// Used when an item is added to a different month: the horizontal jump animation
    /// holds the cache rebuild until it finishes, so the target row doesn't exist yet
    /// when the jump completion fires. Storing the ID here and consuming it in
    /// onChange(of: renderVersion) guarantees the row is in the list before scrolling.
    @State private var pendingVerticalScrollID: String? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @HighlightColorStorage private var highlightColor
    @AppStorage("transactionCategories") private var storedCategories: String = "[]"
    // MARK: - Cached earliest/latest data month (B2: avoids re-scanning dates on every body pass)
    @State private var cachedEarliestYM: YearMonth? = nil
    @State private var cachedLatestYM: YearMonth? = nil

    // MARK: - Debounced year-boundary save (B4)
    @State private var yearSaveTask: Task<Void, Never>?
    @State private var ymPersistTask: Task<Void, Never>?

    /// Seeds the transaction arrays synchronously at construction time (mirroring
    /// loadBudgetData()'s decode + 30-day-trash-cleanup step) rather than leaving them at
    /// their `= []` defaults until handleAppear's onAppear fires. Restoring an edit target
    /// (expenseToEdit, attachmentToView, etc.) on cold launch pushes its
    /// navigationDestination(item:) in the very same tick this view first appears; that
    /// destination's SafeBindingHelper lookup closes over `expenses` as of this view's
    /// *first* body evaluation, so if the array were still empty at that point the lookup
    /// would fail even though handleAppear fills it in moments later. Seeding here instead
    /// means the first body evaluation already has the real data, so no defer is needed and
    /// the restored edit page opens instantly instead of flashing the plain budget page
    /// first. handleAppear's loadBudgetData() still runs and redundantly reloads the same
    /// data — that duplication is harmless and keeps this initializer as the only special case.
    init(item: Item) {
        self.item = item
        let data = item.decodeBudgetData()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var initialExpenses = data?.expenses ?? []
        var initialIncomes = data?.incomes ?? []
        var initialAttachments = data?.attachments ?? []
        let initialReallocations = data?.reallocations ?? []
        let initialOdometerReadings = data?.odometerReadings ?? []
        initialExpenses.removeAll { $0.deletedDate != nil && $0.deletedDate! < thirtyDaysAgo }
        initialIncomes.removeAll { $0.deletedDate != nil && $0.deletedDate! < thirtyDaysAgo }
        initialAttachments.removeAll { $0.deletedDate != nil && $0.deletedDate! < thirtyDaysAgo }
        self._expenses = State(initialValue: initialExpenses)
        self._incomes = State(initialValue: initialIncomes)
        self._attachments = State(initialValue: initialAttachments)
        self._reallocations = State(initialValue: initialReallocations)
        self._odometerReadings = State(initialValue: initialOdometerReadings)

        // Resolve any item-identity restoration target (Edit Expense/Income/Reallocation/
        // Odometer Reading, or the attachment viewer) synchronously here, before this view's
        // first body evaluation. Unlike every boolean-flag restored page (Details/Income/
        // Filter/Add, handled in handleAppear), navigationDestination(item:)'s destination-
        // building closure doesn't pick up state — including a bound draft passed to the
        // pushed Edit view's own init — set later in onAppear; only a value already present
        // at construction time reaches it reliably.
        var initialExpenseToEdit: Expense?
        var initialIncomeToEdit: Income?
        var initialReallocationToEdit: Reallocation?
        var initialOdometerReadingToEdit: OdometerReading?
        var initialAttachmentToView: BudgetAttachment?
        var initialExpenseOccurrenceDate: Date?
        var initialIncomeOccurrenceDate: Date?
        var initialExpenseDraft: TransactionFormDraft?
        var initialIncomeDraft: TransactionFormDraft?
        var initialReallocationDraft: ReallocationFormDraft?
        var initialOdometerDraft: OdometerReadingFormDraft?

        if let pendingSubpage = NavigationStateManager.shared.pendingSubpageRestore,
           pendingSubpage.itemTimestamp == item.timestamp {
            switch pendingSubpage.subpage {
            case .attachment(let attachmentID):
                if let attachment = initialAttachments.first(where: { $0.id == attachmentID }) {
                    initialAttachmentToView = attachment
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                }
            case .editExpense(let id, let occurrenceDate):
                if let expense = initialExpenses.first(where: { $0.id == id && $0.deletedDate == nil }) {
                    initialExpenseOccurrenceDate = occurrenceDate
                    if case .expenseOrIncome(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        initialExpenseDraft = draft
                    }
                    initialExpenseToEdit = expense
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                }
            case .editIncome(let id, let occurrenceDate):
                if let income = initialIncomes.first(where: { $0.id == id && $0.deletedDate == nil }) {
                    initialIncomeOccurrenceDate = occurrenceDate
                    if case .expenseOrIncome(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        initialIncomeDraft = draft
                    }
                    initialIncomeToEdit = income
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                }
            case .editReallocation(let id):
                if let reallocation = initialReallocations.first(where: { $0.id == id }) {
                    if case .reallocation(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        initialReallocationDraft = draft
                    }
                    initialReallocationToEdit = reallocation
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                }
            case .editOdometerReading(let id):
                if let reading = initialOdometerReadings.first(where: { $0.id == id }) {
                    if case .odometerReading(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        initialOdometerDraft = draft
                    }
                    initialOdometerReadingToEdit = reading
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                }
            default:
                break // Boolean-flag cases (Details/Income/Filter/Add) are handled in handleAppear.
            }
        }

        self._expenseToEdit = State(initialValue: initialExpenseToEdit)
        self._incomeToEdit = State(initialValue: initialIncomeToEdit)
        self._reallocationToEdit = State(initialValue: initialReallocationToEdit)
        self._odometerReadingToEdit = State(initialValue: initialOdometerReadingToEdit)
        self._attachmentToView = State(initialValue: initialAttachmentToView)
        self._expenseOccurrenceDate = State(initialValue: initialExpenseOccurrenceDate)
        self._incomeOccurrenceDate = State(initialValue: initialIncomeOccurrenceDate)
        self._restoreExpenseDraft = State(initialValue: initialExpenseDraft)
        self._restoreIncomeDraft = State(initialValue: initialIncomeDraft)
        self._restoreReallocationDraft = State(initialValue: initialReallocationDraft)
        self._restoreOdometerDraft = State(initialValue: initialOdometerDraft)
    }

    // MARK: - Carousel Month Range

    /// Returns the cached earliest data month, computed once after load/edit rather than
    /// on every body pass. Falls back to current month when no data exists.
    private var earliestDataYearMonth: YearMonth {
        let now = Date()
        return cachedEarliestYM ?? YearMonth(year: now.year, month: now.month)
    }

    private func recomputeEarliestYM() {
        let now = Date()
        let current = YearMonth(year: now.year, month: now.month)
        let dataDates = incomes.filter { $0.deletedDate == nil }.map(\.date) + expenses.filter { $0.deletedDate == nil }.map(\.date)
        if let earliest = dataDates.min() {
            cachedEarliestYM = YearMonth(year: Calendar.current.component(.year, from: earliest),
                                         month: Calendar.current.component(.month, from: earliest))
        } else {
            cachedEarliestYM = current
        }
        if let latest = dataDates.max() {
            cachedLatestYM = YearMonth(year: Calendar.current.component(.year, from: latest),
                                       month: Calendar.current.component(.month, from: latest))
        } else {
            cachedLatestYM = current
        }
        rebuildCarouselMonths()
    }

    /// Cached carousel month array. Stored in @State so it is only rebuilt when data changes
    /// or focusedYearMonth goes beyond the current upper bound — not on every body pass during swipes.
    @State private var carouselMonths: [YearMonth] = []

    /// Rebuilds the carousel month array. Always spans at least 24 months (2 years) in each
    /// direction from the current year, extended further if data exists outside that window.
    private func rebuildCarouselMonths() {
        let now = Date()
        let currentYear = now.year
        let dataLatestYear = cachedLatestYM?.year ?? currentYear
        let startYear = min(earliestDataYearMonth.year, currentYear - 25)
        let lower = YearMonth(year: startYear, month: 1)
        let upper = max(YearMonth(year: max(dataLatestYear, currentYear + 5), month: 12), focusedYearMonth)
        carouselMonths = yearMonths(from: lower, through: upper)
    }


    // MARK: - Body

    var body: some View {
        carouselView
        .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { NavigationStateManager.shared.showingUniversalSearch = true } } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .tint(.primary)
                }
                PageNavigationToolbarItem(label: item.displayName, systemImage: "chart.bar.xaxis", titleOnly: true)
                ToolbarItem(placement: .navigationBarLeading) {
                    let hasDaySelection = !(selectedDaysByMonth[focusedYearMonth] ?? []).isEmpty
                    let hasFilterSelection = !selectedTransactionCategories.isEmpty || !selectedTransactionTypes.isDefaultSelection || selectedVehicleFilter != nil
                    Button {
                        selectedDaysByMonth[focusedYearMonth] = []
                        if !selectedTransactionCategories.isEmpty {
                            selectedTransactionCategories = []
                        }
                        if !selectedTransactionTypes.isDefaultSelection {
                            selectedTransactionTypes = .defaultSelection
                        }
                        if selectedVehicleFilter != nil {
                            selectedVehicleFilter = nil
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .tint(.primary)
                    .disabled(!(hasDaySelection || hasFilterSelection))
                }
                bottomBarToolbarItem
            }
            .toolbarRole(.automatic)
            .background { sheetsModifier }
            .background { odometerSheetsModifier }
            .background { alertsModifier }
            // Rebuild the per-month expanded-data cache whenever data changes.
            // Task.yield() between months keeps the main thread free during the loop so
            // ongoing animations and gestures are not starved while rebuilding 50+ months.
            .task(id: dataVersion) {
                guard dataVersion > 0 else { return }
                recomputeEarliestYM()
                let months = carouselMonths
                let weekStartDay = item.effectiveCalendarWeekStartDay
                let isTaxSavingsEnabled = item.isTaxSavingsEnabled
                let taxSavingsPercentage = item.taxSavingsPercentage
                // buildMonthDataCache is @concurrent, so this loop runs on the global concurrent
                // executor rather than the main thread — see its doc comment in BudgetHelpers.swift.
                let result = await buildMonthDataCache(months: months,
                                                       incomes: incomes, expenses: expenses, reallocations: reallocations,
                                                       odometerReadings: odometerReadings,
                                                       weekStartDay: weekStartDay,
                                                       isTaxSavingsEnabled: isTaxSavingsEnabled,
                                                       taxSavingsPercentage: taxSavingsPercentage)
                guard !Task.isCancelled else { return }
                // Defer the re-render until any in-progress carousel animation finishes
                // so the full-cache update doesn't disrupt the page-flip or scroll animation.
                while isJumpAnimating || isCarouselAnimating {
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled else { return }
                }
                monthDataCache = result
                renderVersion += 1
            }
            .onChange(of: focusedYearMonth) { _, newYM in
                NavigationStateManager.shared.viewedYearMonths[item.timestamp] = newYM
                ymPersistTask?.cancel()
                ymPersistTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    NavigationStateManager.shared.saveCurrentYearMonth(newYM)
                }
                if item.targetYear != newYM.year {
                    item.targetYear = newYM.year
                    yearSaveTask?.cancel()
                    yearSaveTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        try? item.modelContext?.save()
                    }
                }
                // Extend the cached range if the user somehow scrolls past the upper bound.
                if let last = carouselMonths.last, newYM > last {
                    rebuildCarouselMonths()
                }
            }
            .onChange(of: showingAddExpense) { old, new in
                if !old && new { expenseCountBeforeAdd = expenses.count }
                else if old && !new, expenses.count > expenseCountBeforeAdd,
                        let newest = expenses.max(by: { $0.createdAt < $1.createdAt }) {
                    let scrollID = "\(newest.id.uuidString)-\(newest.date.timeIntervalSince1970)"
                    let targetYM = YearMonth(year: Calendar.current.component(.year, from: newest.date),
                                            month: Calendar.current.component(.month, from: newest.date))
                    scrollToItemInMonth(scrollID: scrollID, itemYM: targetYM)
                }
            }
            .onChange(of: showingAddIncome) { old, new in
                if !old && new { incomeCountBeforeAdd = incomes.count }
                else if old && !new, incomes.count > incomeCountBeforeAdd,
                        let newest = incomes.max(by: { $0.createdAt < $1.createdAt }) {
                    let scrollID = "\(newest.id.uuidString)-\(newest.date.timeIntervalSince1970)"
                    let targetYM = YearMonth(year: Calendar.current.component(.year, from: newest.date),
                                            month: Calendar.current.component(.month, from: newest.date))
                    scrollToItemInMonth(scrollID: scrollID, itemYM: targetYM)
                }
            }
            .onChange(of: showingReallocateFunds) { old, new in
                if !old && new { reallocationCountBeforeAdd = reallocations.count }
                else if old && !new, reallocations.count > reallocationCountBeforeAdd,
                        let newest = reallocations.filter({ !$0.isFromEntry }).max(by: { $0.createdAt < $1.createdAt }) {
                    let targetYM = YearMonth(year: newest.toYear, month: newest.toMonth)
                    scrollToItemInMonth(scrollID: newest.id.uuidString, itemYM: targetYM)
                }
            }
            .onChange(of: showingAddOdometerReading) { old, new in
                if !old && new { odometerReadingCountBeforeAdd = odometerReadings.count }
                else if old && !new, odometerReadings.count > odometerReadingCountBeforeAdd,
                        let newest = odometerReadings.max(by: { $0.createdAt < $1.createdAt }) {
                    let targetYM = YearMonth(year: newest.date.year, month: newest.date.month)
                    scrollToItemInMonth(scrollID: newest.id.uuidString, itemYM: targetYM)
                }
            }
            .onChange(of: showingBudgetPhotoPicker) { old, new in
                if !old && new { attachmentCountBeforeAdd = attachments.count }
                else if old && !new, attachments.count > attachmentCountBeforeAdd,
                        let newest = attachments.max(by: { $0.dateAdded < $1.dateAdded }) {
                    scrollToNewAttachment(newest.id)
                }
            }
            .onChange(of: showingBudgetFilePicker) { old, new in
                if !old && new { attachmentCountBeforeAdd = attachments.count }
                else if old && !new, attachments.count > attachmentCountBeforeAdd,
                        let newest = attachments.max(by: { $0.dateAdded < $1.dateAdded }) {
                    scrollToNewAttachment(newest.id)
                }
            }
            .onChange(of: showingEditDetails) { _, newValue in
                if !newValue {
                    if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        item.name = "Budget"
                    }
                    // Defer reload until after the dismiss animation to avoid jank.
                    // Picks up any trash changes made inside the Details sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        loadBudgetData()
                    }
                }
            }
            // MonthPageView now reads header totals and the calendar grid from monthDataCache
            // instead of recomputing them from `item` on every body pass, so a settings change
            // needs an explicit rebuild to appear immediately (BudgetDetailsView commits these
            // synchronously on Save, before the sheet dismiss animation the handler above waits on).
            .onChange(of: item.isTaxSavingsEnabled) { _, _ in rebuildFocusedMonthCache() }
            .onChange(of: item.taxSavingsPercentage) { _, _ in rebuildFocusedMonthCache() }
            .onChange(of: item.effectiveCalendarWeekStartDay) { _, _ in rebuildFocusedMonthCache() }
            // Bump renderVersion whenever display state that affects MonthPageView changes.
            // These are the @Binding-sourced values that MonthPageView.Equatable cannot
            // compare directly (both sides read the same live @State, always equal).
            .onChange(of: selectedTransactionTypes) { _, _ in renderVersion += 1 }
            .onChange(of: selectedTransactionCategories) { _, _ in renderVersion += 1 }
            .onChange(of: selectedVehicleFilter) { _, _ in renderVersion += 1 }
            .onChange(of: selectedExpenses) { _, _ in renderVersion += 1 }
            .onChange(of: selectedIncomes) { _, _ in renderVersion += 1 }
            .onChange(of: selectedReallocations) { _, _ in renderVersion += 1 }
            .onChange(of: selectedAttachments) { _, _ in renderVersion += 1 }
            .onChange(of: selectedDaysByMonth) { _, _ in renderVersion += 1 }
            // Deliver a pending cross-month vertical scroll once the cache has been rebuilt.
            // The background task sets renderVersion after writing monthDataCache, so by the
            // time this fires the target month's row is guaranteed to exist in the list.
            .onChange(of: renderVersion) { _, _ in
                guard let scrollID = pendingVerticalScrollID else { return }
                pendingVerticalScrollID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .scrollToNewItem, object: scrollID)
                }
            }
            .onAppear { handleAppear() }
            .onDisappear { handleDisappear() }
            .onChange(of: NavigationStateManager.shared.pendingScrollTarget) { _, target in
                guard let target, target.itemTimestamp == item.timestamp else { return }
                NavigationStateManager.shared.pendingScrollTarget = nil
                scrollToItemInMonth(scrollID: target.scrollID, itemYM: target.yearMonth)
            }
            .onChange(of: NavigationStateManager.shared.pendingAddSheet) { _, pending in
                guard let pending, pending.itemTimestamp == item.timestamp else { return }
                NavigationStateManager.shared.pendingAddSheet = nil
                let currentYM = YearMonth(year: Date().year, month: Date().month)
                if focusedYearMonth != currentYM {
                    focusedYearMonth = currentYM
                    jump(to: currentYM)
                }
                presentAddSheet(pending.kind)
            }
            .onChange(of: NavigationStateManager.shared.pendingBudgetDetailsTimestamp) { _, pendingTimestamp in
                guard let pendingTimestamp, pendingTimestamp == item.timestamp else { return }
                NavigationStateManager.shared.pendingBudgetDetailsTimestamp = nil
                showingEditDetails = true
            }
            .onChange(of: currentSubpage) { _, newValue in
                NavigationStateManager.shared.saveSubpage(newValue, for: item.timestamp)
            }
            // Pages are pushed via navigationDestination(isPresented:)/(item:) rather than
            // living in navigationPath, so a path change alone doesn't dismiss them. When
            // navigation jumps to a destination that's already showing (e.g. search or a
            // quick action retargeting this same budget), NavigationStateManager bumps this
            // token so any page pushed from here gets popped.
            .onChange(of: NavigationStateManager.shared.dismissPresentedPagesToken) { _, _ in
                showingEditDetails = false
                showingIncomeView = false
                showingAddExpense = false
                showingAddIncome = false
                showingReallocateFunds = false
                showingAddOdometerReading = false
                showingFilterAndTypeSheet = false
                expenseToEdit = nil
                incomeToEdit = nil
                reallocationToEdit = nil
                odometerReadingToEdit = nil
                attachmentToView = nil
            }
            .onBudgetDataChange(
                expenses: expenses, incomes: incomes,
                attachments: attachments, reallocations: reallocations,
                odometerReadings: odometerReadings,
                isInitialLoad: isInitialLoad, persist: { persistBudgetData() }
            )
            .onCategoryRenamed(expenses: $expenses, incomes: $incomes)
            .onCategoryDeleted(expenses: $expenses, incomes: $incomes)
            .onReceive(NotificationCenter.default.publisher(for: .sharedAttachmentsImported)) { _ in
                loadBudgetData()
            }
    }

    // MARK: - Carousel View

    private var carouselView: some View {
        // ScrollView with paging avoids the UIKit UICollectionView that TabView(.page)
        // uses internally — that UICollectionView double-counted the NavigationStack's
        // bottom toolbar safe area inset, leaving a large empty gap at the bottom of
        // every page. A pure SwiftUI ScrollView lets the embedded List manage its own
        // content insets correctly against the glass toolbar.
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(carouselMonths) { ym in
                    monthPage(ym)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(ym)
                }
            }
            .scrollTargetLayout()
            .background(CarouselScrollFinder(driver: carouselDriver))
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding<YearMonth?>(
            get: { isCarouselAnimating ? nil : focusedYearMonth },
            set: { if let ym = $0, !isCarouselAnimating { focusedYearMonth = ym } }
        ))
        .scrollDisabled(isJumpAnimating)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }

    private func monthPage(_ ym: YearMonth) -> some View {
        MonthPageView(
            yearMonth: ym,
            item: item,
            dataVersion: dataVersion,
            renderVersion: renderVersion,
            precomputedData: monthDataCache[ym] ?? .empty,
            expenses: $expenses,
            incomes: $incomes,
            attachments: $attachments,
            reallocations: $reallocations,
            odometerReadings: $odometerReadings,
            selectedTransactionTypes: $selectedTransactionTypes,
            selectedTransactionCategories: $selectedTransactionCategories,
            selectedVehicleFilter: $selectedVehicleFilter,
            selectedExpenses: $selectedExpenses,
            selectedIncomes: $selectedIncomes,
            selectedReallocations: $selectedReallocations,
            selectedAttachments: $selectedAttachments,
            onEditExpense: { expense, date in
                expenseOccurrenceDate = date
                expenseToEdit = expense
            },
            onEditIncome: { income, date in
                incomeOccurrenceDate = date
                incomeToEdit = income
            },
            onViewAttachment: { attachmentToView = $0 },
            onEditReallocation: { reallocationToEdit = $0 },
            onDeleteReallocation: { reallocation in
                reallocationToDelete = reallocation
                showingDeleteConfirmation = true
            },
            onEditOdometerReading: { odometerReadingToEdit = $0 },
            onDeleteOdometerReading: { reading in
                odometerReadingToDelete = reading
                showingDeleteConfirmation = true
            },
            onDeleteExpense: { requestDeleteExpense($0) },
            onDeleteIncome: { requestDeleteIncome($0) },
            onDuplicateExpense: { requestDuplicateExpense($0, adjustedDate: $1) },
            onDuplicateIncome: { requestDuplicateIncome($0, adjustedDate: $1) },
            onPayOffExpense: { payOffExpense($0) },
            yearRange: {
                let currentYear = Date().year
                let dataLatestYear = cachedLatestYM?.year ?? currentYear
                let startYear = min(earliestDataYearMonth.year, currentYear - 25)
                let upperYear = max(dataLatestYear, currentYear + 5)
                return startYear...upperYear
            }(),
            onJumpToMonth: { ym in
                if ym != focusedYearMonth {
                    jump(to: ym)
                } else {
                    // Re-selecting the current month scrolls to the top — acts as a "reset" gesture.
                    NotificationCenter.default.post(name: .scrollPageToTop, object: nil)
                }
            },
            selectedDays: Binding(
                get: { selectedDaysByMonth[ym] ?? [] },
                set: { selectedDaysByMonth[ym] = $0 }
            ),
            scrollToCalendarOnAppear: scrollToCalendarYM == ym,
            onScrollToCalendarTriggered: { scrollToCalendarYM = nil },
            isActive: focusedYearMonth == ym
        )
        .equatable()
        // The reference itself never changes, so this write is a no-op to SwiftUI's diffing —
        // see EnvironmentValues.selectionMode for why that's what keeps MonthPageView's body
        // from rerunning when selection mode toggles.
        .environment(\.selectionMode, selectionMode)
    }

    // MARK: - Carousel Navigation

    /// Moves the carousel to a target month using a frame-by-frame sine ease-in-out
    /// driven by CarouselJumpDriver.
    ///
    /// Long jumps (> 2 pages): teleports to 2 pages before the target so the driver only
    /// traverses 2 pages. A snapshot of the current state is driven in lockstep by the
    /// driver — same easing curve, frame-perfect sync — hiding the instant position jump
    /// and acting as an "outgoing page" that slides off in the direction of travel.
    ///
    /// The optional `then` closure fires on the next runloop tick after the animation ends.
    private func jump(to target: YearMonth, then action: (() -> Void)? = nil) {
        guard target != focusedYearMonth else { return }
        guard let sv = carouselDriver.scrollView,
              let targetIndex = carouselMonths.firstIndex(of: target) else {
            // Fallback before the view has appeared or if target isn't in the array.
            focusedYearMonth = target
            action?()
            return
        }
        let pageWidth = sv.bounds.width
        let targetX = CGFloat(targetIndex) * pageWidth
        let direction: CGFloat = targetX > sv.contentOffset.x ? 1 : -1
        let nearX = max(0, min(targetX - direction * pageWidth, sv.contentSize.width - pageWidth))

        // For multi-page jumps, teleport to one page before the target and cover the
        // instant position change with a snapshot that slides out in perfect lockstep with
        // the incoming page — both travel one page width on the same CADisplayLink curve.
        var companion: (view: UIView, fromTx: CGFloat, toTx: CGFloat)? = nil
        if abs(sv.contentOffset.x - nearX) > 1, let superview = sv.superview,
           let snapshot = sv.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = sv.convert(sv.bounds, to: superview)
            superview.addSubview(snapshot)
            sv.setContentOffset(CGPoint(x: nearX, y: sv.contentOffset.y), animated: false)
            companion = (snapshot, 0, -direction * pageWidth)
        }

        isJumpAnimating = true
        isCarouselAnimating = true

        carouselDriver.animate(toX: targetX, duration: 0.5, companion: companion) {
            // Disable SwiftUI animations for these mutations so the scrollPosition
            // binding transition (nil → target) is instant. Without this, SwiftUI
            // starts its own reconciliation animation for long jumps where the
            // destination page is freshly entering the viewport, causing visible
            // horizontal movement after the CarouselJumpDriver animation ends.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                self.focusedYearMonth = target
                // Re-enable scrolling after animation. Keeping it disabled during the
                // programmatic scroll prevents a mid-flight touch from leaving the view
                // between page boundaries and causing the next swipe to get stuck.
                self.isJumpAnimating = false
                self.isCarouselAnimating = false
            }
            if let action { DispatchQueue.main.async { action() } }
        }
    }

    private func scrollToNewItem(scrollID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: .scrollToNewItem,
                object: scrollID
            )
        }
    }

    private func scrollToItemInMonth(scrollID: String, itemYM: YearMonth) {
        if itemYM != focusedYearMonth {
            jump(to: itemYM) {
                // Don't post the scroll notification here — the cache rebuild task is
                // blocked on isJumpAnimating and won't finish until after this closure
                // fires. Storing the ID for delivery on the next renderVersion bump
                // ensures the target row is in the list before we try to scroll to it.
                pendingVerticalScrollID = scrollID
            }
        } else {
            scrollToNewItem(scrollID: scrollID)
        }
    }

    private func scrollToNewAttachment(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .scrollToNewItem, object: id)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var bottomBarToolbarItem: some ToolbarContent {
        if selectionMode.isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                let focusedCache = monthDataCache[focusedYearMonth] ?? .empty
                let expandedInc = focusedCache.expandedIncomes
                let expandedExp = focusedCache.expandedExpenses
                let monthReallocations = focusedCache.activeReallocations
                let monthAtt = focusedMonthAttachments

                // Mirror the type-filter logic from MonthPageView so counts match what's visible
                let typeInc: [Income] = {
                    guard !selectedTransactionTypes.isDefaultSelection && !selectedTransactionTypes.contains(.income) else { return expandedInc }
                    return expandedInc.filter { i in
                        (selectedTransactionTypes.contains(.otherIncome) && !i.isTaxable) ||
                        (selectedTransactionTypes.contains(.taxableIncome) && i.isTaxable) ||
                        (selectedTransactionTypes.contains(.recurringIncome) && i.isRecurring) ||
                        (selectedTransactionTypes.contains(.oneTimeIncome) && !i.isRecurring)
                    }
                }()
                let typeExp: [Expense] = {
                    guard !selectedTransactionTypes.isDefaultSelection && !selectedTransactionTypes.contains(.expenses) else { return expandedExp }
                    return expandedExp.filter { e in
                        (selectedTransactionTypes.contains(.recurringExpenses) && e.isRecurring) ||
                        (selectedTransactionTypes.contains(.paymentPlans) && e.isMonthlyPaymentPlan) ||
                        (selectedTransactionTypes.contains(.oneTimeExpense) && !e.isRecurring && !e.isMonthlyPaymentPlan)
                    }
                }()
                let typeReallocs: [Reallocation] = {
                    // Reallocations have no categories, so narrowing to a specific category
                    // hides the Reallocations section entirely — mirror that here.
                    guard selectedTransactionCategories.isEmpty else { return [] }
                    guard !selectedTransactionTypes.isDefaultSelection && !selectedTransactionTypes.contains(.reallocations) else { return monthReallocations }
                    return monthReallocations.filter { r in
                        (selectedTransactionTypes.contains(.positiveReallocation) && !r.isFromEntry) ||
                        (selectedTransactionTypes.contains(.negativeReallocation) && r.isFromEntry)
                    }
                }()
                // Apply category filter to income and expenses
                let visibleInc: [Income] = {
                    guard !selectedTransactionCategories.isEmpty else { return typeInc }
                    let uncategorized = selectedTransactionCategories.contains(SettingsDefault.uncategorizedSentinel)
                    return typeInc.filter { i in
                        uncategorized
                            ? (i.categories.isEmpty || i.categories.contains(SettingsDefault.uncategorizedSentinel))
                            : i.categories.contains(where: { selectedTransactionCategories.contains($0) })
                    }
                }()
                let visibleExp: [Expense] = {
                    guard !selectedTransactionCategories.isEmpty else { return typeExp }
                    let uncategorized = selectedTransactionCategories.contains(SettingsDefault.uncategorizedSentinel)
                    return typeExp.filter { e in
                        uncategorized
                            ? (e.categories.isEmpty || e.categories.contains(SettingsDefault.uncategorizedSentinel))
                            : e.categories.contains(where: { selectedTransactionCategories.contains($0) })
                    }
                }()

                let totalItems = visibleInc.count + visibleExp.count + typeReallocs.count + monthAtt.count
                let totalSelected = visibleInc.filter { selectedIncomes.contains(OccurrenceKey(id: $0.id, date: $0.date)) }.count +
                                    visibleExp.filter { selectedExpenses.contains(OccurrenceKey(id: $0.id, date: $0.date)) }.count +
                                    typeReallocs.filter { selectedReallocations.contains($0.id) }.count +
                                    monthAtt.filter { selectedAttachments.contains($0.id) }.count
                let selectAllText = totalSelected == 0 ? "Select All" : (totalSelected == totalItems ? "Deselect All" : "Select All")
                let hasSelection = !selectedExpenses.isEmpty || !selectedIncomes.isEmpty || !selectedReallocations.isEmpty || !selectedAttachments.isEmpty

                Button { exitSelectionMode() } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.primary)

                Spacer()

                Button {
                    if totalSelected == totalItems {
                        visibleInc.forEach { selectedIncomes.remove(OccurrenceKey(id: $0.id, date: $0.date)) }
                        visibleExp.forEach { selectedExpenses.remove(OccurrenceKey(id: $0.id, date: $0.date)) }
                        typeReallocs.forEach { selectedReallocations.remove($0.id) }
                        monthAtt.forEach { selectedAttachments.remove($0.id) }
                    } else {
                        visibleInc.forEach { selectedIncomes.insert(OccurrenceKey(id: $0.id, date: $0.date)) }
                        visibleExp.forEach { selectedExpenses.insert(OccurrenceKey(id: $0.id, date: $0.date)) }
                        typeReallocs.forEach { selectedReallocations.insert($0.id) }
                        monthAtt.forEach { selectedAttachments.insert($0.id) }
                    }
                } label: {
                    Label(selectAllText, systemImage: totalSelected == totalItems ? "checklist.unchecked" : "checklist.checked")
                }
                .tint(.primary)

                Button(role: .destructive) {
                    guard hasSelection else { return }
                    showingBulkDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        } else {
            ToolbarItemGroup(placement: .bottomBar) {
                let focusedCache = monthDataCache[focusedYearMonth] ?? .empty
                Button { withAnimation { selectionMode.isSelecting = true } } label: {
                    Label("Select", systemImage: "checklist")
                }
                .tint(.primary)
                .disabled(focusedCache.expandedIncomes.isEmpty
                          && focusedCache.expandedExpenses.isEmpty
                          && focusedCache.activeReallocations.isEmpty
                          && focusedMonthAttachments.isEmpty)

                Spacer()

                Button { showingIncomeView = true } label: {
                    Label("Year Overview", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tint(.primary)

                Spacer()

                Button { showingEditDetails = true } label: {
                    Label("Budget Details", systemImage: "square.and.pencil")
                }
                .tint(.primary)

                Spacer()

                Button { showingFilterAndTypeSheet = true } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
                .tint((!selectedTransactionTypes.isDefaultSelection || !selectedTransactionCategories.isEmpty || selectedVehicleFilter != nil) ? highlightColor : .primary)

                Spacer()

                Button {
                    let currentYM = YearMonth(year: Date().year, month: Date().month)
                    if currentYM != focusedYearMonth {
                        jump(to: currentYM)
                    } else {
                        let calendarID = "calendarSection-\(currentYM.year)-\(currentYM.month)"
                        NotificationCenter.default.post(name: .scrollToNewItem, object: calendarID)
                    }
                } label: {
                    Label("Current Month", systemImage: "mappin.and.ellipse")
                }
                .tint(focusedYearMonth == YearMonth(year: Date().year, month: Date().month) ? highlightColor : .primary)

                Spacer()

                Menu {
                    Button { showingAddOdometerReading = true } label: {
                        Label("Odometer Reading", systemImage: "speedometer")
                    }
                    Button { showingReallocateFunds = true } label: {
                        Label("Reallocate Funds", systemImage: "arrow.left.arrow.right")
                    }
                    Button { showingAddExpense = true } label: {
                        Label("Expense", systemImage: "cart")
                    }
                    Button { showingAddIncome = true } label: {
                        Label("Income", systemImage: "dollarsign.circle")
                    }
                    Button { showingBudgetPhotoPicker = true } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    Button { showingBudgetFilePicker = true } label: {
                        Label("File", systemImage: "doc")
                    }
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .tint(.primary)
                .id("budgetAddMenu-\(item.id)")
            }
        }
    }

    private var focusedMonthAttachments: [BudgetAttachment] {
        attachments.filter { $0.month == focusedYearMonth.month && $0.year == focusedYearMonth.year && $0.deletedDate == nil }
    }

    /// The page currently pushed on top of this budget's page, for restoration purposes.
    /// Add and Edit forms alike report just their kind/target here — the in-progress field
    /// values (including which attachment, if any, was being viewed) are tracked separately
    /// as an AddSheetDraft since they change on every keystroke; see AddExpenseView/
    /// EditExpenseView/etc. Nested pages (Budget Trash inside Details, an attachment inside
    /// Income) report their own, more specific value once opened; see BudgetDetailsView/
    /// BudgetIncomeSheetView.
    private var currentSubpage: SavedSubpage? {
        if showingEditDetails { return .budgetDetails }
        if showingIncomeView { return .income }
        if showingFilterAndTypeSheet { return .filter }
        if showingAddExpense { return .addExpense }
        if showingAddIncome { return .addIncome }
        if showingReallocateFunds { return .addReallocation }
        if showingAddOdometerReading { return .addOdometerReading }
        if let expense = expenseToEdit { return .editExpense(id: expense.id, occurrenceDate: expenseOccurrenceDate) }
        if let income = incomeToEdit { return .editIncome(id: income.id, occurrenceDate: incomeOccurrenceDate) }
        if let reallocation = reallocationToEdit { return .editReallocation(id: reallocation.id) }
        if let reading = odometerReadingToEdit { return .editOdometerReading(id: reading.id) }
        if let attachment = attachmentToView { return .attachment(attachment.id) }
        return nil
    }

    // MARK: - Sheets

    private var sheetsModifier: some View {
        Color.clear
            .navigationDestination(isPresented: $showingEditDetails) {
                BudgetDetailsView(
                    item: item,
                    restoreBudgetTrash: $restoreBudgetDetailsTrash,
                    initialDraft: $restoreBudgetDetailsDraft,
                    onSave: { showingEditDetails = false },
                    onCancel: { showingEditDetails = false }
                )
            }
            .navigationDestination(isPresented: $showingIncomeView) {
                BudgetIncomeSheetView(item: item, incomes: $incomes, expenses: $expenses, attachments: $attachments, odometerReadings: $odometerReadings, initialAttachmentID: $restoreIncomeAttachmentID)
            }
            .navigationDestination(isPresented: $showingAddExpense) {
                AddExpenseView(expenses: $expenses,
                               incomes: $incomes,
                               selectedMonth: focusedYearMonth.month,
                               selectedYear: focusedYearMonth.year,
                               selectedDay: defaultDay(for: focusedYearMonth, selectedDays: []),
                               defaultDate: defaultDate(for: focusedYearMonth, selectedDays: []),
                               item: item,
                               initialDraft: $restoreExpenseDraft)
            }
            .navigationDestination(isPresented: $showingAddIncome) {
                AddIncomeView(incomes: $incomes, expenses: $expenses, item: item, showRecurringOption: true, defaultShowDate: true, showMonthSelector: false,
                              selectedMonth: focusedYearMonth.month,
                              selectedYear: focusedYearMonth.year,
                              selectedDay: defaultDay(for: focusedYearMonth, selectedDays: []),
                              defaultDate: defaultDate(for: focusedYearMonth, selectedDays: []),
                              initialDraft: $restoreIncomeDraft)
            }
            .navigationDestination(isPresented: $showingReallocateFunds) {
                ReallocateFundsView(reallocations: $reallocations, expenses: $expenses, incomes: $incomes, item: item, selectedMonth: nil, selectedYear: nil, initialDraft: $restoreReallocationDraft)
            }
            .navigationDestination(item: $expenseToEdit) { expense in
                if let expenseBinding = SafeBindingHelper.binding(for: expense, in: $expenses) {
                    EditExpenseView(expense: expenseBinding, expenses: $expenses, incomes: $incomes, occurrenceDate: expenseOccurrenceDate ?? expense.date, item: item, initialDraft: $restoreExpenseDraft)
                } else {
                    Color.clear.task { expenseToEdit = nil }
                }
            }
            .navigationDestination(item: $incomeToEdit) { income in
                if let incomeBinding = SafeBindingHelper.binding(for: income, in: $incomes) {
                    EditIncomeView(income: incomeBinding, incomes: $incomes, expenses: $expenses, item: item, occurrenceDate: incomeOccurrenceDate ?? income.date, initialDraft: $restoreIncomeDraft)
                } else {
                    Color.clear.task { incomeToEdit = nil }
                }
            }
            .navigationDestination(item: $reallocationToEdit) { reallocation in
                if let reallocationBinding = SafeBindingHelper.binding(for: reallocation, in: $reallocations) {
                    EditReallocateFundsView(reallocation: reallocationBinding, reallocations: $reallocations, expenses: $expenses, incomes: $incomes, item: item, initialDraft: $restoreReallocationDraft)
                } else {
                    Color.clear.task { reallocationToEdit = nil }
                }
            }
            .navigationDestination(item: $attachmentToView) { (attachment: BudgetAttachment) in
                BudgetAttachmentViewerSheet(attachments: $attachments, attachment: attachment)
            }
            .navigationDestination(isPresented: $showingFilterAndTypeSheet) {
                FilterAndTypeSheet(
                    selectedTransactionTypes: $selectedTransactionTypes,
                    selectedTransactionCategories: $selectedTransactionCategories,
                    selectedVehicle: $selectedVehicleFilter,
                    item: item,
                    month: focusedYearMonth.month,
                    year: focusedYearMonth.year
                )
            }

            .budgetAttachmentPickers(
                showingPhotoPicker: $showingBudgetPhotoPicker,
                showingFilePicker: $showingBudgetFilePicker,
                attachments: $attachments,
                month: focusedYearMonth.month,
                year: focusedYearMonth.year
            )

    }

    /// Odometer add/edit sheets, split out of `sheetsModifier` to keep that modifier chain
    /// short enough for the type-checker.
    private var odometerSheetsModifier: some View {
        Color.clear
            .navigationDestination(isPresented: $showingAddOdometerReading) {
                AddOdometerReadingView(odometerReadings: $odometerReadings,
                                        item: item,
                                        selectedMonth: focusedYearMonth.month,
                                        selectedYear: focusedYearMonth.year,
                                        selectedDay: defaultDay(for: focusedYearMonth, selectedDays: []),
                                        defaultDate: defaultDate(for: focusedYearMonth, selectedDays: []),
                                        initialDraft: $restoreOdometerDraft)
            }
            .navigationDestination(item: $odometerReadingToEdit) { reading in
                if let readingBinding = SafeBindingHelper.binding(for: reading, in: $odometerReadings) {
                    EditOdometerReadingView(reading: readingBinding, odometerReadings: $odometerReadings, item: item, initialDraft: $restoreOdometerDraft)
                } else {
                    Color.clear.task { odometerReadingToEdit = nil }
                }
            }
    }

    // MARK: - Alerts

    private var alertsModifier: some View {
        Color.clear
            .background {
                AlertContainer {
                    Color.clear
                        .alert(getDeleteAlertTitle(), isPresented: $showingDeleteConfirmation) {
                            Button("Cancel", role: .cancel) {
                                expenseToDelete = nil; incomeToDelete = nil
                                reallocationToDelete = nil; odometerReadingToDelete = nil
                                pendingRecurringScope = nil
                            }
                            Button(isTrashableDelete ? "Confirm" : "Delete", role: .destructive) { handleSingleDelete() }
                        } message: {
                            Text(getDeleteAlertMessage())
                        }
                }
            }
            .background {
                AlertContainer {
                    Color.clear
                        .alert("Delete Selected Items?", isPresented: $showingBulkDeleteConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) { handleBulkDelete() }
                        } message: {
                            let total = selectedExpenses.count + selectedIncomes.count + selectedReallocations.count + selectedAttachments.count
                            Text("This will delete \(total) item\(total == 1 ? "" : "s"). Non-recurring items will be moved to Trash. Recurring items are permanently deleted (current occurrence only).")
                        }
                }
            }
            .background {
                AlertContainer {
                    Color.clear
                        .alert("Delete Recurring Item", isPresented: $showingRecurringScopeAlert) {
                            Button("All Occurrences", role: .destructive) {
                                pendingRecurringScope = .all
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                            }
                            Button("Current And Future", role: .destructive) {
                                pendingRecurringScope = .currentAndFuture
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                            }
                            Button("Current Occurrence", role: .destructive) {
                                pendingRecurringScope = .currentOnly
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                            }
                            Button("Cancel", role: .cancel) {
                                expenseToDelete = nil; incomeToDelete = nil
                            }
                        } message: {
                            Text("This is a recurring item. Choose which occurrences to delete:")
                        }
                }
            }
            .background {
                AlertContainer {
                    Color.clear
                        .alert("Duplicate Recurring Item", isPresented: $showingRecurringDuplicateScopeAlert) {
                            Button("All Occurrences") { performDuplicate(scope: .all) }
                            Button("Current And Future") { performDuplicate(scope: .currentAndFuture) }
                            Button("Current Occurrence") { performDuplicate(scope: .currentOnly) }
                            Button("Cancel", role: .cancel) { clearDuplicateState() }
                        } message: {
                            Text("This is a recurring item. Choose which occurrences to duplicate:")
                        }
                }
            }
    }

    // MARK: - Appear / Load

    private func handleAppear() {
        // When the user starts a horizontal drag, animate the visible page's first
        // section to center so it's ready before the swipe settles. Reassigned on every
        // appear (cheap) since it's a closure capture, not state that needs guarding.
        carouselDriver.onUserDragBegan = {
            guard !isJumpAnimating, !isCarouselAnimating else { return }
            NotificationCenter.default.post(name: .scrollPageToFirstSection, object: nil)
        }

        // Everything below should only run the first time this instance appears. Pages
        // are pushed via navigationDestination(isPresented:)/(item:) rather than shown as
        // sheets, so — unlike a sheet, which never disappeared the presenter underneath —
        // popping back to this page fires onAppear again. Reloading here on every pop
        // would be wasted work and could flicker; returning from Details/Trash reloads
        // explicitly via onChange(of: showingEditDetails) instead.
        guard !didInitialAppear else { return }
        didInitialAppear = true

        isInitialLoad = true
        if carouselMonths.isEmpty { rebuildCarouselMonths() }

        // Restore the scroll position before loading data so the initial 3-month cache
        // is built around the correct month. Restoring after loadBudgetData caused the
        // restored month to be missing from the cache, showing placeholders until the
        // full background task completed.
        var searchScrollID: String?
        if let target = NavigationStateManager.shared.pendingScrollTarget,
           target.itemTimestamp == item.timestamp {
            NavigationStateManager.shared.pendingScrollTarget = nil
            focusedYearMonth = target.yearMonth
            searchScrollID = target.scrollID
        } else if let restored = NavigationStateManager.shared.viewedYearMonths[item.timestamp] {
            focusedYearMonth = restored
            NavigationStateManager.shared.viewedYearMonths[item.timestamp] = nil
        }

        loadBudgetData()

        if let pending = NavigationStateManager.shared.pendingAddSheet,
           pending.itemTimestamp == item.timestamp {
            NavigationStateManager.shared.pendingAddSheet = nil
            let kind = pending.kind
            // Delay until after the navigation push animation finishes (~0.35s) so the
            // sheet presentation isn't swallowed while the transition is in flight.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                presentAddSheet(kind)
            }
        }

        if let pendingDetailsTimestamp = NavigationStateManager.shared.pendingBudgetDetailsTimestamp,
           pendingDetailsTimestamp == item.timestamp {
            NavigationStateManager.shared.pendingBudgetDetailsTimestamp = nil
            // Delay until after the navigation push animation finishes (~0.35s) so the
            // sheet presentation isn't swallowed while the transition is in flight.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                showingEditDetails = true
            }
        }

        // Restore a page saved on top of this budget's page (Details, Income, Filter, or
        // Add) left over from ContentView.restoreFullNavigationState because this item was
        // at the top of the restored stack. Applied synchronously and with animations
        // disabled, since there's no user tap or in-flight push transition here to wait out
        // — the page should just already be open. The item-identity cases (attachment/edit
        // targets) are handled by the custom init above instead of here — see its comment
        // for why navigationDestination(item:) needs that earlier timing.
        if let pendingSubpage = NavigationStateManager.shared.pendingSubpageRestore,
           pendingSubpage.itemTimestamp == item.timestamp {
            withoutAnimation {
                switch pendingSubpage.subpage {
                case .budgetDetails:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    if case .budgetDetails(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        restoreBudgetDetailsDraft = draft
                    }
                    showingEditDetails = true
                case .budgetDetailsTrash:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    restoreBudgetDetailsTrash = true
                    if case .budgetDetails(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        restoreBudgetDetailsDraft = draft
                    }
                    showingEditDetails = true
                case .income:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    showingIncomeView = true
                case .incomeAttachment(let attachmentID):
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    restoreIncomeAttachmentID = attachmentID
                    showingIncomeView = true
                case .filter:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    showingFilterAndTypeSheet = true
                case .addExpense:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    if case .expenseOrIncome(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        restoreExpenseDraft = draft
                    }
                    showingAddExpense = true
                case .addIncome:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    if case .expenseOrIncome(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        restoreIncomeDraft = draft
                    }
                    showingAddIncome = true
                case .addReallocation:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    if case .reallocation(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        restoreReallocationDraft = draft
                    }
                    showingReallocateFunds = true
                case .addOdometerReading:
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                    if case .odometerReading(let draft)? = NavigationStateManager.shared.loadDraft(for: item.timestamp) {
                        restoreOdometerDraft = draft
                    }
                    showingAddOdometerReading = true
                case .attachment, .editExpense, .editIncome, .editReallocation, .editOdometerReading:
                    // Already consumed synchronously in init above (which also clears
                    // pendingSubpageRestore on a match). Still non-nil here means the target
                    // wasn't found there either (e.g. deleted between save and launch) —
                    // clear it so it doesn't linger.
                    NavigationStateManager.shared.pendingSubpageRestore = nil
                }
            }
        }

        if let scrollID = searchScrollID {
            scrollToNewItem(scrollID: scrollID)
        }

        item.lastOpenedDate = Date()
        try? item.modelContext?.save()

        // The root UIHostingView fills the entire screen but the paging TabView only
        // occupies the content area. The UIHostingView's backgroundColor shows in the
        // gaps around the toolbar material. Deferred to the next run loop so the view
        // hierarchy is fully laid out before we modify it.
        DispatchQueue.main.async {
            keyWindow?.rootViewController?.view.backgroundColor = .systemGroupedBackground
        }
    }

    private func handleDisappear() {
        // No reset needed — systemGroupedBackground is correct for all screens in this app.
    }

    private func presentAddSheet(_ kind: AddSheetKind) {
        switch kind {
        case .expense:      showingAddExpense = true
        case .income:       showingAddIncome = true
        case .reallocation: showingReallocateFunds = true
        case .photo:        showingBudgetPhotoPicker = true
        case .file:         showingBudgetFilePicker = true
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// Loads all budget data from the item's encoded blob into the shared arrays (once).
    private func loadBudgetData() {
        if let data = item.decodeBudgetData() {
            expenses = data.expenses; incomes = data.incomes
            attachments = data.attachments; reallocations = data.reallocations
            odometerReadings = data.odometerReadings
        } else {
            expenses = []; incomes = []; attachments = []; reallocations = []; odometerReadings = []
        }
        // Permanently remove items that have been in trash for more than 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        expenses.removeAll { $0.deletedDate != nil && $0.deletedDate! < thirtyDaysAgo }
        incomes.removeAll { $0.deletedDate != nil && $0.deletedDate! < thirtyDaysAgo }
        attachments.removeAll { $0.deletedDate != nil && $0.deletedDate! < thirtyDaysAgo }
        recomputeEarliestYM()
        // Pre-build the focused month + 4 neighbors in each direction synchronously so that
        // those pages of the LazyHStack render from warm cache immediately with no empty-data
        // placeholder flash. The full background task fills in all remaining months.
        let weekStartDay = item.effectiveCalendarWeekStartDay
        let isTaxSavingsEnabled = item.isTaxSavingsEnabled
        let taxSavingsPercentage = item.taxSavingsPercentage
        var initial: [YearMonth: MonthExpandedData] = [:]
        for offset in -4...4 {
            let ym = offsetYearMonth(focusedYearMonth, by: offset)
            initial[ym] = buildMonthData(incomes: incomes, expenses: expenses,
                                         reallocations: reallocations, odometerReadings: odometerReadings, ym: ym,
                                         weekStartDay: weekStartDay,
                                         isTaxSavingsEnabled: isTaxSavingsEnabled,
                                         taxSavingsPercentage: taxSavingsPercentage)
        }
        monthDataCache = initial
        dataVersion += 1   // triggers full background cache build via .task(id: dataVersion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInitialLoad = false
        }
    }

    private func persistBudgetData() {
        saveBudgetData(to: item, expenses: expenses, incomes: incomes,
                       attachments: attachments, reallocations: reallocations,
                       odometerReadings: odometerReadings)
        // Immediately rebuild the focused month's cache so adds/edits/deletes
        // appear in the list without waiting for the background task. The equatable
        // check on MonthPageView only re-renders when dataVersion changes; since
        // the background task sets monthDataCache = result AFTER dataVersion was
        // already bumped, equatable would return true and suppress the re-render.
        // Updating the cache here first ensures the body re-runs with correct data
        // the moment dataVersion bumps below.
        rebuildFocusedMonthCache()
    }

    /// Synchronously rebuilds the focused month ± 1 in `monthDataCache` and bumps `dataVersion`
    /// so the visible page reflects a change immediately, while the background task
    /// (`.task(id: dataVersion)`) backfills every other month. Used after data mutations
    /// (`persistBudgetData`) and after tax/calendar settings change, since MonthPageView now
    /// reads precomputed header totals rather than recomputing them from `item` on every body pass.
    private func rebuildFocusedMonthCache() {
        let weekStartDay = item.effectiveCalendarWeekStartDay
        let isTaxSavingsEnabled = item.isTaxSavingsEnabled
        let taxSavingsPercentage = item.taxSavingsPercentage
        for offset in -1...1 {
            let ym = offsetYearMonth(focusedYearMonth, by: offset)
            monthDataCache[ym] = buildMonthData(incomes: incomes, expenses: expenses,
                                                reallocations: reallocations, odometerReadings: odometerReadings, ym: ym,
                                                weekStartDay: weekStartDay,
                                                isTaxSavingsEnabled: isTaxSavingsEnabled,
                                                taxSavingsPercentage: taxSavingsPercentage)
        }
        dataVersion += 1   // triggers full background cache rebuild for all months
    }

    // MARK: - Row Interaction Requests

    private func requestDeleteExpense(_ expense: Expense) {
        expenseToDelete = expense
        if expense.isMonthlyPaymentPlan {
            pendingRecurringScope = .all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
        } else if expense.isRecurring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingRecurringScopeAlert = true }
        } else {
            pendingRecurringScope = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
        }
    }

    private func requestDeleteIncome(_ income: Income) {
        incomeToDelete = income
        if income.isRecurring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingRecurringScopeAlert = true }
        } else {
            pendingRecurringScope = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
        }
    }

    private func requestDuplicateExpense(_ expense: Expense, adjustedDate: Date) {
        expenseToDuplicate = expense
        expenseAdjustedDate = adjustedDate
        if expense.isMonthlyPaymentPlan {
            pendingRecurringScope = .all
            copyExpense(expense, adjustedDate: adjustedDate)
            clearDuplicateState()
        } else if expense.isRecurring {
            showingRecurringDuplicateScopeAlert = true
        } else {
            pendingRecurringScope = nil
            copyExpense(expense, adjustedDate: adjustedDate)
            clearDuplicateState()
        }
    }

    private func requestDuplicateIncome(_ income: Income, adjustedDate: Date) {
        incomeToDuplicate = income
        incomeAdjustedDate = adjustedDate
        if income.isRecurring {
            showingRecurringDuplicateScopeAlert = true
        } else {
            pendingRecurringScope = nil
            copyIncome(income, adjustedDate: adjustedDate)
            clearDuplicateState()
        }
    }

    // MARK: - Duplicate / Copy Logic

    private func clearDuplicateState() {
        expenseToDuplicate = nil
        incomeToDuplicate = nil
        expenseAdjustedDate = nil
        incomeAdjustedDate = nil
    }

    private func performDuplicate(scope: RecurringScope) {
        pendingRecurringScope = scope
        if let expense = expenseToDuplicate, let adjustedDate = expenseAdjustedDate {
            copyExpense(expense, adjustedDate: adjustedDate)
        } else if let income = incomeToDuplicate, let adjustedDate = incomeAdjustedDate {
            copyIncome(income, adjustedDate: adjustedDate)
        }
        clearDuplicateState()
    }

    private func copyRecurringItem<T: RecurringItem>(_ item: T, adjustedDate: Date?, into array: inout [T], onCurrentOnly: ((inout T) -> Void)? = nil) {
        let startDate = adjustedDate ?? item.date
        guard let scope = pendingRecurringScope else {
            var copy = item.duplicate(); copy.date = startDate
            array.append(copy)
            return
        }
        switch scope {
        case .currentOnly:
            var copy = item.duplicate()
            copy.date = startDate; copy.endDate = nil; copy.showEndDate = false
            copy.isRecurring = false
            onCurrentOnly?(&copy)
            array.append(copy)
        case .currentAndFuture:
            var copy = item.duplicate(); copy.date = startDate
            array.append(copy)
        case .all:
            array.append(item.duplicate())
        }
        pendingRecurringScope = nil
    }

    private func copyExpense(_ expense: Expense, adjustedDate: Date? = nil) {
        copyRecurringItem(expense, adjustedDate: adjustedDate, into: &expenses) { $0.isMonthlyPaymentPlan = false }
    }

    private func copyIncome(_ income: Income, adjustedDate: Date? = nil) {
        copyRecurringItem(income, adjustedDate: adjustedDate, into: &incomes)
    }

    private func payOffExpense(_ expense: Expense) {
        var income = makeIncomeFromExpense(expense)
        if let swap = reimbursementCategorySwap(
            expenseCategories: expense.categories,
            storedCategories: storedCategories.asCategories,
            hiddenCategories: item.hiddenFilterCategories?.asCategories ?? []
        ) {
            income.categories = swap.incomeCategories
            if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
                expenses[idx].categories = swap.expenseCategories
            }
        }
        incomes.append(income)
        if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[idx].reimbursedByIncomeId = income.id
        }
    }

    // MARK: - Deletion Logic

    private func removeExpense(_ expense: Expense) {
        // Soft-delete non-recurring items and "all occurrences" scope — they go to trash for 30 days.
        // Partial recurring deletions (currentOnly, currentAndFuture) split the item in place
        // and cannot be trivially restored, so they remain immediate hard-deletes.
        if expense.isEffectivelyRecurring, let scope = pendingRecurringScope, scope != .all {
            applyRecurringItemDeletion(item: expense, items: &expenses, pendingScope: &pendingRecurringScope)
        } else {
            let now = Date()
            for i in expenses.indices where expenses[i].id == expense.id {
                expenses[i].deletedDate = now
            }
            pendingRecurringScope = nil
        }
    }

    private func removeIncome(_ income: Income) {
        if income.isEffectivelyRecurring, let scope = pendingRecurringScope, scope != .all {
            applyRecurringItemDeletion(item: income, items: &incomes, pendingScope: &pendingRecurringScope)
        } else {
            let now = Date()
            for i in incomes.indices where incomes[i].id == income.id {
                incomes[i].deletedDate = now
            }
            pendingRecurringScope = nil
        }
    }

    /// When a reimbursement income is deleted, reverts the linked expense's category
    /// from "Reimbursed" back to "Pending Reimbursement".
    private func reverseReimbursementCategories(forIncomeId incomeId: UUID) {
        guard let idx = expenses.firstIndex(where: { $0.reimbursedByIncomeId == incomeId }) else { return }
        expenses[idx].reimbursedByIncomeId = nil
        let stored = storedCategories.asCategories
        let hidden = item.hiddenFilterCategories?.asCategories ?? []
        let pending = "Pending Reimbursement"
        let reimbursed = "Reimbursed"
        let reimbursement = "Reimbursement"
        guard stored.contains(pending), stored.contains(reimbursed), stored.contains(reimbursement),
              !hidden.contains(pending), !hidden.contains(reimbursed), !hidden.contains(reimbursement),
              expenses[idx].categories.contains(reimbursed) else { return }
        expenses[idx].categories.removeAll { $0 == reimbursed }
        if !expenses[idx].categories.contains(pending) {
            expenses[idx].categories.append(pending)
        }
    }

    private func handleSingleDelete() {
        if let expense = expenseToDelete {
            removeExpense(expense); expenseToDelete = nil
        } else if let income = incomeToDelete {
            reverseReimbursementCategories(forIncomeId: income.id)
            removeIncome(income); incomeToDelete = nil
        } else if let reallocation = reallocationToDelete {
            reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
            reallocationToDelete = nil
        } else if let reading = odometerReadingToDelete {
            odometerReadings.removeAll { $0.id == reading.id }
            odometerReadingToDelete = nil
        }
        pendingRecurringScope = nil
    }

    private func handleBulkDelete() {
        let now = Date()
        for occKey in selectedExpenses {
            if let expense = expenses.first(where: { $0.id == occKey.id }) {
                if expense.isRecurring || expense.isMonthlyPaymentPlan {
                    deleteCurrentOccurrenceOfExpense(expense, occurrenceDate: occKey.date)
                } else if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
                    expenses[idx].deletedDate = now
                }
            }
        }
        for occKey in selectedIncomes {
            if let income = incomes.first(where: { $0.id == occKey.id }) {
                if income.isRecurring {
                    deleteCurrentOccurrenceOfIncome(income, occurrenceDate: occKey.date)
                } else {
                    reverseReimbursementCategories(forIncomeId: income.id)
                    if let idx = incomes.firstIndex(where: { $0.id == income.id }) {
                        incomes[idx].deletedDate = now
                    }
                }
            }
        }
        for reallocationID in selectedReallocations {
            if let reallocation = reallocations.first(where: { $0.id == reallocationID }) {
                reallocations.removeAll { $0.id == reallocation.id || $0.id == reallocation.linkedId }
            }
        }
        let attachmentDeleteDate = Date()
        for attachmentID in selectedAttachments {
            if let idx = attachments.firstIndex(where: { $0.id == attachmentID }) {
                attachments[idx].deletedDate = attachmentDeleteDate
            }
        }
        exitSelectionMode()
        pendingRecurringScope = nil
    }

    private func deleteCurrentOccurrenceOfExpense(_ expense: Expense, occurrenceDate: Date) {
        guard let adjusted = expense.withOccurrenceDate(day: occurrenceDate.day, month: occurrenceDate.month, year: occurrenceDate.year) else { return }
        pendingRecurringScope = .currentOnly
        removeExpense(adjusted)
    }

    private func deleteCurrentOccurrenceOfIncome(_ income: Income, occurrenceDate: Date) {
        guard let adjusted = income.withOccurrenceDate(day: occurrenceDate.day, month: occurrenceDate.month, year: occurrenceDate.year) else { return }
        pendingRecurringScope = .currentOnly
        removeIncome(adjusted)
    }

    private func scopeDeletionSuffix(for scope: RecurringScope?) -> String {
        guard let scope else { return "" }
        switch scope {
        case .currentOnly: return " from this month only"
        case .currentAndFuture: return " from this month and all future occurrences"
        case .all: return " (all occurrences)"
        }
    }

    /// True when the pending delete will soft-delete to trash rather than permanently destroy.
    private var isTrashableDelete: Bool {
        if let expense = expenseToDelete {
            return !expense.isEffectivelyRecurring || pendingRecurringScope == .all
        }
        if let income = incomeToDelete {
            return !income.isEffectivelyRecurring || pendingRecurringScope == .all
        }
        return false
    }

    private func getDeleteAlertTitle() -> String {
        if expenseToDelete != nil || incomeToDelete != nil {
            return isTrashableDelete ? "Move to Trash?" : "Delete Item?"
        }
        if reallocationToDelete != nil { return "Delete Reallocation?" }
        if odometerReadingToDelete != nil { return "Delete Odometer Reading?" }
        return "Delete Item?"
    }

    private func getDeleteAlertMessage() -> String {
        if let expense = expenseToDelete {
            if isTrashableDelete {
                return "'\(expense.name)' will be moved to Trash and permanently deleted after 30 days."
            }
            return "This will permanently delete '\(expense.name)'\(scopeDeletionSuffix(for: pendingRecurringScope)). This action cannot be undone."
        } else if let income = incomeToDelete {
            if isTrashableDelete {
                return "'\(income.name)' will be moved to Trash and permanently deleted after 30 days."
            }
            return "This will permanently delete '\(income.name)'\(scopeDeletionSuffix(for: pendingRecurringScope)). This action cannot be undone."
        } else if let reallocation = reallocationToDelete {
            let monthName = monthDisplayName(reallocation.isFromEntry ? reallocation.toMonth : reallocation.fromMonth)
            let year = reallocation.isFromEntry ? reallocation.toYear : reallocation.fromYear
            let autoTitle = reallocation.isFromEntry ? "To \(monthName) \(year)" : "From \(monthName) \(year)"
            return "This will permanently delete the reallocation '\(autoTitle)'. This action cannot be undone."
        } else if let reading = odometerReadingToDelete {
            return "This will permanently delete the odometer reading for '\(reading.vehicle)'. This action cannot be undone."
        }
        return "This action cannot be undone."
    }

    // MARK: - Selection Mode

    private func exitSelectionMode() {
        withAnimation {
            selectionMode.isSelecting = false
            selectedExpenses.removeAll()
            selectedIncomes.removeAll()
            selectedReallocations.removeAll()
            selectedAttachments.removeAll()
        }
    }

}

