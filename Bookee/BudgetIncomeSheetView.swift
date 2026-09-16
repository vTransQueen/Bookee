//
//  BudgetIncomeSheetView.swift
//  Bookee
//
//  Sheet view showing a yearly overview of taxable income and tax calculations
//  for a budget item, with per-month totals and attachment support.
//


import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers


// MARK: - Year Overview Page (single carousel page)

private struct YearOverviewPage: View {
    let year: Int
    @Bindable var item: Item
    @Binding var attachments: [BudgetAttachment]
    @Binding var attachmentToView: BudgetAttachment?
    let yearRange: ClosedRange<Int>
    /// Pre-computed year metrics from BudgetIncomeSheetView's background cache task.
    let precomputedMetrics: MonthMetrics
    /// Pre-computed total miles driven this year, from BudgetIncomeSheetView's background cache task.
    let milesDriven: Int
    /// Incremented by BudgetIncomeSheetView when the metrics cache is rebuilt.
    let dataVersion: Int
    /// Incremented by BudgetIncomeSheetView when display state (attachments) changes.
    let renderVersion: Int
    /// True only for the page currently visible in the carousel. Guards scroll-to-top.
    let isActive: Bool
    let onJumpToYear: (Int) -> Void

    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @HighlightColorStorage private var highlightColor

    private var yearAttachmentsBinding: Binding<[BudgetAttachment]> {
        Binding(
            get: { attachments.filter { $0.year == year && $0.deletedDate == nil } },
            set: { newYearAttachments in
                let deletedOnes = attachments.filter { $0.year == year && $0.deletedDate != nil }
                attachments.removeAll { $0.year == year }
                attachments.append(contentsOf: newYearAttachments)
                attachments.append(contentsOf: deletedOnes)
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                metricsSection
                BudgetAttachmentManagementView(
                    attachments: yearAttachmentsBinding,
                    attachmentToView: $attachmentToView,
                    alwaysShow: true,
                    isSelecting: false,
                    selectedAttachments: .constant(Set<UUID>()),
                    highlightColor: highlightColor
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .onReceive(NotificationCenter.default.publisher(for: .scrollSheetPageToFirstSection)) { _ in
                guard isActive else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
                    proxy.scrollTo("yearOverview-top-\(year)", anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        Section {
            MonthOverviewRowsView(
                m: precomputedMetrics,
                item: item,
                selectedCurrency: selectedCurrency,
                yearMonth: nil,
                navigationPath: nil,
                hideReallocations: true
            )
            .id("yearOverview-top-\(year)")

            HStack {
                Text("Miles Driven")
                    .fontWeight(.medium)
                Spacer()
                Text("\(milesDriven) mi")
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
            }
        } header: {
            HStack {
                Menu {
                    Picker(
                        selection: Binding(get: { year }, set: { onJumpToYear($0) })
                    ) {
                        ForEach(yearRange.reversed(), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                } label: {
                    Text(String(year))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                Spacer()
            }
        }
    }
}

// MARK: - YearOverviewPage Equatable

/// Equality is defined over the inputs that actually affect rendering. Closures (callbacks) are
/// intentionally excluded — they are always new instances each parent body pass but are
/// functionally identical, so excluding them lets .equatable() skip re-renders during swipes.
/// @Bindable `item` changes are handled by SwiftUI's observation system independently.
extension YearOverviewPage: Equatable {
    static func == (lhs: YearOverviewPage, rhs: YearOverviewPage) -> Bool {
        lhs.year == rhs.year
        && lhs.dataVersion == rhs.dataVersion
        && lhs.renderVersion == rhs.renderVersion
        && lhs.isActive == rhs.isActive
        && lhs.milesDriven == rhs.milesDriven
    }
}


// MARK: - Budget Income Sheet View

/// Sheet view that displays a yearly overview of taxable income and tax calculations
/// Shows income totals by month and attachments for the selected year
/// Replicates the IncomePageView functionality in a sheet format
struct BudgetIncomeSheetView: View {
    @Bindable var item: Item
    @Binding var incomes: [Income]
    @Binding var expenses: [Expense]
    @Binding var attachments: [BudgetAttachment]
    @Binding var odometerReadings: [OdometerReading]
    // Set by the presenter when restoring a saved `.incomeAttachment` subpage, so this
    // instance auto-opens that attachment on first appear. Consumed and cleared immediately.
    var initialAttachmentID: Binding<UUID?> = .constant(nil)
    @State private var attachmentToView: BudgetAttachment?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @HighlightColorStorage private var highlightColor

    // MARK: - Carousel state

    @State private var focusedYear: Int = Date().year
    @State private var isJumpAnimating = false
    @State private var isCarouselAnimating = false
    @State private var carouselDriver = CarouselJumpDriver()
    @State private var carouselYears: [Int] = []

    // MARK: - Pre-computed year metrics cache

    /// Incremented when the year range or data changes; triggers the background cache-rebuild task.
    @State private var dataVersion: Int = 0
    /// Incremented when display state (attachments) changes so .equatable() pages re-render.
    @State private var renderVersion: Int = 0
    /// Pre-computed MonthMetrics per year, built off the main thread with Task.yield() gaps.
    @State private var yearMetricsCache: [Int: MonthMetrics] = [:]
    /// Pre-computed total miles driven per year, built alongside `yearMetricsCache`.
    @State private var yearMilesDrivenCache: [Int: Int] = [:]

    // MARK: - Year range (cached)

    /// Cached year range — computed once on appear and when the carousel is extended,
    /// rather than on every body pass. Avoids O(n) date scans during swipes.
    @State private var cachedYearRange: ClosedRange<Int> = (Date().year - 25)...(Date().year + 5)

    private func computeYearRange() -> ClosedRange<Int> {
        let currentYear = Date().year
        let allDates = incomes.filter { $0.deletedDate == nil }.map(\.date) +
                       expenses.filter { $0.deletedDate == nil }.map(\.date)
        let years = allDates.map { Calendar.current.component(.year, from: $0) }
        let lower = min(years.min() ?? (currentYear - 25), currentYear - 25)
        let upper = max(years.max() ?? (currentYear + 5), currentYear + 5)
        return lower...upper
    }

    private func rebuildCarouselYears() {
        let range = computeYearRange()
        cachedYearRange = range
        carouselYears = Array(range)
    }

    // MARK: - Year metrics builder

    /// Computes MonthMetrics for a single year from the current incomes/expenses/item.
    /// Extracted here so the .task can call it cooperatively between years.
    private func buildYearMetrics(year: Int) -> MonthMetrics {
        let activeExpenses = expenses.filter { $0.deletedDate == nil }
        let activeIncomes  = incomes.filter  { $0.deletedDate == nil }
        let expByYM = groupByYearMonth(activeExpenses, selectedYear: year)
        let incByYM = groupByYearMonth(activeIncomes,  selectedYear: year)

        var totalTaxableIncome: Decimal = 0
        var totalUntaxableIncome: Decimal = 0
        var totalExpenses: Decimal = 0

        for month in 1...12 {
            let ym = YearMonth(year: year, month: month)
            for income in incByYM[ym] ?? [] {
                let amount = effectiveMonthlyAmount(for: income, month: month, year: year) ?? income.amount
                if item.isTaxSavingsEnabled && income.isTaxable {
                    totalTaxableIncome = roundMoney(totalTaxableIncome + amount)
                } else {
                    totalUntaxableIncome = roundMoney(totalUntaxableIncome + amount)
                }
            }
            for expense in expByYM[ym] ?? [] {
                let amount = effectiveMonthlyAmount(for: expense, month: month, year: year) ?? expense.amount
                totalExpenses = roundMoney(totalExpenses + amount)
            }
        }

        let filteredTaxableIncomes = activeIncomes
            .filter { $0.isTaxable && isItemInYear(year, startDate: $0.date, endDate: $0.endDate) }
        let taxableIncByYM = groupByYearMonth(filteredTaxableIncomes, selectedYear: year)
        let totalTaxSavings: Decimal = item.isTaxActive
            ? allYearMonths(for: year).map { ym -> Decimal in
                let pairs = (taxableIncByYM[ym] ?? []).map { income in
                    (income: income, amount: effectiveMonthlyAmount(for: income, month: ym.month, year: ym.year) ?? income.amount)
                }
                return TaxDistributionHelper.distributedTaxAmounts(for: pairs, defaultPercentage: item.taxSavingsPercentage).values.sumMoney()
              }.sumMoney()
            : 0

        var remaining: Decimal = 0
        remaining = roundMoney(remaining + totalUntaxableIncome)
        remaining = roundMoney(remaining + totalTaxableIncome)
        if item.isTaxActive { remaining = roundMoney(remaining - totalTaxSavings) }
        remaining = roundMoney(remaining - totalExpenses)
        remaining = remaining.roundedAndNormalizedMoney()

        let expensesCoveredByUntaxable = roundMoney(min(totalExpenses, totalUntaxableIncome))
        let remainingAfterUntaxable = roundMoney(max(0, totalExpenses - expensesCoveredByUntaxable))
        let divisor = 1 - item.taxRate
        let needed = divisor == 0 ? remainingAfterUntaxable : roundMoney(remainingAfterUntaxable / divisor)
        let s1 = roundMoney(expensesCoveredByUntaxable + needed)
        let s2 = roundMoney(s1 - totalUntaxableIncome)
        let incomeNeeded = max(0, roundMoney(s2 - totalTaxableIncome))

        let breakEven: Decimal = {
            if item.isTaxActive {
                let afterTax = roundMoney(totalTaxableIncome - totalTaxSavings)
                let available = roundMoney(afterTax + totalUntaxableIncome)
                return max(0, roundMoney(totalExpenses - available))
            } else {
                return max(0, roundMoney(totalExpenses - roundMoney(totalTaxableIncome + totalUntaxableIncome)))
            }
        }()

        return MonthMetrics(
            taxableIncome: totalTaxableIncome,
            untaxableIncome: totalUntaxableIncome,
            expenses: totalExpenses,
            reallocated: 0,
            positiveReallocation: 0,
            negativeReallocation: 0,
            incomeNeeded: incomeNeeded,
            breakEven: breakEven,
            remaining: remaining,
            taxSavings: totalTaxSavings
        )
    }

    // MARK: - Carousel page builder

    private func yearPage(_ year: Int) -> some View {
        YearOverviewPage(
            year: year,
            item: item,
            attachments: $attachments,
            attachmentToView: $attachmentToView,
            yearRange: cachedYearRange,
            precomputedMetrics: yearMetricsCache[year] ?? .empty,
            milesDriven: yearMilesDrivenCache[year] ?? 0,
            dataVersion: dataVersion,
            renderVersion: renderVersion,
            isActive: focusedYear == year,
            onJumpToYear: { newYear in jump(to: newYear) }
        )
        .equatable()
    }

    // MARK: - Carousel navigation

    /// Moves the carousel to a target year using a frame-by-frame sine ease-in-out
    /// driven by CarouselJumpDriver. Mirrors jump(to:then:) in BudgetPageView exactly.
    private func jump(to target: Int, then action: (() -> Void)? = nil) {
        guard target != focusedYear else { return }
        guard let sv = carouselDriver.scrollView,
              let targetIndex = carouselYears.firstIndex(of: target) else {
            focusedYear = target
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
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                self.focusedYear = target
                self.isJumpAnimating = false
                self.isCarouselAnimating = false
            }
            if let action { DispatchQueue.main.async { action() } }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var incomeToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { dismiss() } label: {
                Text("Year Overview")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize()
            }
            .tint(.primary)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            Button {
                let currentYear = Date().year
                if currentYear != focusedYear {
                    jump(to: currentYear)
                } else {
                    NotificationCenter.default.post(name: .scrollSheetPageToFirstSection, object: nil)
                }
            } label: {
                Label("Current Year", systemImage: "mappin.and.ellipse")
            }
            .tint(focusedYear == Date().year ? highlightColor : .primary)
        }
    }

    // MARK: - Body

    /// Guards the one-time setup in `onAppear` so returning from a pushed page (e.g. an
    /// attachment viewer) doesn't reset the focused year or rebuild the carousel again.
    @State private var hasAppeared = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(carouselYears, id: \.self) { year in
                    yearPage(year)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(year)
                }
            }
            .scrollTargetLayout()
            .background(CarouselScrollFinder(driver: carouselDriver))
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding<Int?>(
            get: { isCarouselAnimating ? nil : focusedYear },
            set: { if let y = $0, !isCarouselAnimating { focusedYear = y } }
        ))
        .scrollDisabled(isJumpAnimating)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            incomeToolbarItems
        }
        .navigationDestination(item: $attachmentToView) { (attachment: BudgetAttachment) in
            BudgetAttachmentViewerSheet(attachments: $attachments, attachment: attachment)
        }
        // Rebuild the per-year metrics cache whenever dataVersion bumps.
        // Task.yield() between years keeps the main thread free during the loop so
        // ongoing animations and gestures are not starved while rebuilding 30+ years.
        .task(id: dataVersion) {
            guard dataVersion > 0 else { return }
            let years = carouselYears
            var result: [Int: MonthMetrics] = [:]
            var milesResult: [Int: Int] = [:]
            for year in years {
                guard !Task.isCancelled else { return }
                result[year] = buildYearMetrics(year: year)
                milesResult[year] = totalMilesDriven(odometerReadings: odometerReadings, year: year)
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            // Defer the cache write until any in-progress carousel animation finishes
            // so the full-cache update doesn't disrupt the page-flip animation.
            while isJumpAnimating || isCarouselAnimating {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
            }
            yearMetricsCache = result
            yearMilesDrivenCache = milesResult
            renderVersion += 1
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            rebuildCarouselYears()
            focusedYear = item.targetYear ?? Date().year
            // When the user starts a horizontal drag, scroll the visible page's
            // metrics section back to the top so it's ready before the swipe settles.
            carouselDriver.onUserDragBegan = {
                guard !isJumpAnimating, !isCarouselAnimating else { return }
                NotificationCenter.default.post(name: .scrollSheetPageToFirstSection, object: nil)
            }
            // Pre-build focused year ±2 synchronously so pages display immediately
            // with real data; the full background task fills in the remaining years.
            if dataVersion == 0 {
                let current = focusedYear
                var initial: [Int: MonthMetrics] = [:]
                var initialMiles: [Int: Int] = [:]
                for offset in -2...2 {
                    let y = current + offset
                    if carouselYears.contains(y) {
                        initial[y] = buildYearMetrics(year: y)
                        initialMiles[y] = totalMilesDriven(odometerReadings: odometerReadings, year: y)
                    }
                }
                yearMetricsCache = initial
                yearMilesDrivenCache = initialMiles
                dataVersion = 1
            }

            if let attachmentID = initialAttachmentID.wrappedValue,
               let attachment = attachments.first(where: { $0.id == attachmentID }) {
                // No user tap or in-flight transition to wait out here — the page should
                // just already be open.
                withoutAnimation {
                    attachmentToView = attachment
                }
            }
            initialAttachmentID.wrappedValue = nil
        }
        .onChange(of: attachmentToView) { _, newValue in
            NavigationStateManager.shared.saveSubpage(newValue.map { .incomeAttachment($0.id) } ?? .income, for: item.timestamp)
        }
        .onChange(of: focusedYear) { _, newYear in
            var needsRebuild = false
            if let last = carouselYears.last, newYear > last { rebuildCarouselYears(); needsRebuild = true }
            if let first = carouselYears.first, newYear < first { rebuildCarouselYears(); needsRebuild = true }
            if needsRebuild { dataVersion += 1 }
        }
        .onChange(of: attachments) { _, _ in
            renderVersion += 1
        }
    }

}
