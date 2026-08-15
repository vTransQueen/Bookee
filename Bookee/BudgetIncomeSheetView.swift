//
//  BudgetIncomeSheetView.swift
//  Bookee
//
//  Sheet view showing a yearly overview of taxable income and tax calculations
//  for a budget item, with per-month totals and attachment support.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers


// MARK: - Budget Income Sheet View

/// Sheet view that displays a yearly overview of taxable income and tax calculations
/// Shows income totals by month and attachments for the selected year
/// Replicates the IncomePageView functionality in a sheet format
struct BudgetIncomeSheetView: View {
    @Bindable var item: Item
    @Binding var incomes: [Income]
    @Binding var attachments: [BudgetAttachment]
    var onNavigateToMonth: ((YearMonth) -> Void)? = nil
    @State private var incomeToEdit: Income?
    @State private var isSelecting = false
    @State private var selectedIncomes = Set<UUID>()
    @State private var selectedYear: Int = Date().year
    @State private var attachmentToView: BudgetAttachment?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .abbreviated
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true
    
    /// Total of all filtered incomes for the selected year
    var totalIncome: Double { filteredIncomes.map(\.amount).sumMoney() }

    /// Total taxable income only (excludes non-taxable income).
    /// filteredIncomes already guarantees every element is taxable, so this equals totalIncome.
    var taxableIncome: Double { totalIncome }

    /// Calculated tax amount based on taxable income and configured tax rate
    var taxSavingsGoal: Double {
        guard item.isTaxActive else { return 0.0 }
        return taxableIncome.taxAmount(rate: item.taxRate)
    }

    /// Filters incomes to only show taxable income items in the selected year
    /// Sorted by date from earliest to latest
    var filteredIncomes: [Income] {
        incomes
            .filter { $0.isTaxable && isItemInYear(selectedYear, startDate: $0.date, endDate: $0.endDate) }
            .sorted { $0.date < $1.date }
    }
    
    var yearAttachments: [BudgetAttachment] {
        attachments.filter { $0.year == selectedYear }
    }
    
    private var yearAttachmentsBinding: Binding<[BudgetAttachment]> {
        Binding(
            get: { attachments.filter { $0.year == selectedYear } },
            set: { newYearAttachments in
                attachments.removeAll { $0.year == selectedYear }
                attachments.append(contentsOf: newYearAttachments)
            }
        )
    }
    
    var incomesByYearMonth: [YearMonth: [Income]] {
        filteredIncomes.reduce(into: [:]) { result, income in
            result[YearMonth(year: income.date.year, month: income.date.month), default: []].append(income)
        }
    }
    
    var visibleYearMonths: [YearMonth] { allYearMonths(for: selectedYear) }
    
    func totalForYearMonth(_ yearMonth: YearMonth) -> Double {
        return (incomesByYearMonth[yearMonth] ?? []).map { $0.amount }.sumMoney()
    }
    
    func taxableIncomeForYearMonth(_ yearMonth: YearMonth) -> Double {
        // When tax savings is disabled, treat all income as non-taxable (return 0 for taxable)
        guard item.isTaxSavingsEnabled else { return 0.0 }
        
        return (incomesByYearMonth[yearMonth] ?? []).map { $0.amount }.sumMoney()
    }
    
    /// Distributes the yearly Tax Percentage across months using the largest-remainder method,
    /// ensuring the sum of per-month tax savings equals the yearly total shown in the header.
    private var distributedMonthlyTaxSavings: [YearMonth: Double] {
        guard item.isTaxActive else { return [:] }
        let buckets: [(key: YearMonth, taxableAmount: Double)] = visibleYearMonths.compactMap { ym in
            let taxable = taxableIncomeForYearMonth(ym)
            guard taxable.isEffectivelyPositive else { return nil }
            return (key: ym, taxableAmount: taxable)
        }
        return TaxDistributionHelper.distributedTaxAmounts(buckets: buckets, taxRate: item.taxRate)
    }

    func taxSavingsForYearMonth(_ yearMonth: YearMonth) -> Double {
        // Use distributed values so that monthly totals sum exactly to the yearly header total.
        return distributedMonthlyTaxSavings[yearMonth] ?? 0.0
    }
    
    @ViewBuilder
    private func makeIncomeOverviewSection() -> some View {
        let isTaxEnabled = item.isTaxSavingsEnabled
        let taxPercentage = item.taxSavingsPercentage
        
        Section {
            // Add all month rows in the same section
            ForEach(visibleYearMonths, id: \.self) { yearMonth in
                yearMonthHeaderRow(for: yearMonth)
            }
        } header: {
            makeIncomeOverviewHeader(isTaxEnabled: isTaxEnabled)
        } footer: {
            if showFooters {
                let taxText = isTaxEnabled && taxPercentage.isEffectivelyPositive
                    ? "Tax Percentage: \(PercentageFormatter.formatForTextField(taxPercentage))%. "
                    : (isTaxEnabled ? "Tax Percentage: 0%. " : "Tax Percentage: disabled. ")
                
                Text("\(taxText)Only taxable income is displayed.")
                    .font(.footnote)
            }
        }
    }
    
    @ViewBuilder
    private func makeIncomeOverviewHeader(isTaxEnabled: Bool) -> some View {
        HStack {
            Text("Income/Taxes").fontWeight(.medium)
            Spacer()
            if isTaxEnabled {
                makeTaxAndIncomeView(taxSavings: taxSavingsGoal, total: totalIncome)
            } else {
                makeIncomeOnlyView(total: totalIncome)
            }
        }
        .textCase(nil)
    }
    
    @ViewBuilder
    private func yearMonthHeaderRow(for yearMonth: YearMonth) -> some View {
        let total = totalForYearMonth(yearMonth)
        let monthTaxSavings = taxSavingsForYearMonth(yearMonth)
        let isTaxEnabled = item.isTaxSavingsEnabled

        Button {
            onNavigateToMonth?(yearMonth)
        } label: {
            HStack {
                Text(yearMonth.displayName)
                    .fontWeight(.medium)
                Spacer()

                if isTaxEnabled {
                    makeTaxAndIncomeView(taxSavings: monthTaxSavings, total: total)
                } else {
                    makeIncomeOnlyView(total: total)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // Helper view for tax-enabled display
    @ViewBuilder
    private func makeTaxAndIncomeView(taxSavings: Double, total: Double) -> some View {
        HStack(spacing: 4) {
            Text(total, format: .currency(code: selectedCurrency.code))
                .foregroundStyle(.green)
                .fontWeight(.medium)
            Text("/")
                .foregroundStyle(.primary)
            Text(taxSavings, format: .currency(code: selectedCurrency.code))
                .foregroundStyle(.orange)
                .fontWeight(.medium)
        }
    }
    
    // Helper view for income-only display
    @ViewBuilder
    private func makeIncomeOnlyView(total: Double) -> some View {
        Text(total, format: .currency(code: selectedCurrency.code))
            .foregroundStyle(.green)
            .fontWeight(.medium)
    }
    
    private var incomePageTitle: String {
        return "\(selectedYear) Overview"
    }
    
    @ToolbarContentBuilder
    private var incomeToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                let currentYear = Date().year
                let startYear = currentYear - 24
                ForEach((startYear...currentYear).reversed(), id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        HStack {
                            Text(String(year))
                            if selectedYear == year {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(incomePageTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 200)
            }
            .tint(.primary)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.primary)
        }
    }
    
    @ToolbarContentBuilder
    private var bottomBarToolbarItem: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                makeIncomeOverviewSection()
                makeAttachmentsSection()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("All Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                incomeToolbarItems
                bottomBarToolbarItem
            }
        }
        .standardSheetPresentation()
        .sheet(item: $attachmentToView) { (attachment: BudgetAttachment) in
            BudgetAttachmentViewerSheet(attachments: $attachments, attachment: attachment)
        }
        .onAppear {
            if let targetYear = item.targetYear {
                selectedYear = targetYear
            }
        }
    }
    
    @ViewBuilder
    private func makeAttachmentsSection() -> some View {
        BudgetAttachmentManagementView(
            attachments: yearAttachmentsBinding,
            attachmentToView: $attachmentToView,
            alwaysShow: true,
            isSelecting: false,
            selectedAttachments: .constant(Set<UUID>()),
            highlightColor: highlightColor
        )
    }
    
    // MARK: - Helper Methods

    private func removeIncome(_ income: Income) {
        incomes.removeAll { $0.id == income.id }
    }
    
    private func copyIncome(_ income: Income) {
        incomes.append(income.duplicate())
    }
    
    private func toggleIncomeSelectionState(for income: Income) {
        selectedIncomes.toggle(income.id)
    }
    
    private func selectAllIncomes() {
        selectedIncomes = Set(incomes.map(\.id))
    }
    
    private func removeSelectedIncomes() {
        incomes.removeAll { selectedIncomes.contains($0.id) }
        selectedIncomes.removeAll()
        isSelecting = false
    }
}


