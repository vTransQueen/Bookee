//
//  ViewExtensions.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Budget Data Change Modifier

/// Attaches the identical `onChange(of:)` guard-and-persist handlers shared by
/// BudgetPageView and MonthDetailsPageView.
extension View {
    func onBudgetDataChange(
        expenses: [Expense],
        incomes: [Income],
        attachments: [BudgetAttachment],
        reallocations: [Reallocation],
        odometerReadings: [OdometerReading],
        isInitialLoad: Bool,
        persist: @escaping () -> Void
    ) -> some View {
        self
            .onChange(of: expenses)         { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: incomes)          { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: attachments)      { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: reallocations)    { _, _ in if !isInitialLoad { persist() } }
            .onChange(of: odometerReadings) { _, _ in if !isInitialLoad { persist() } }
    }
}

// MARK: - Selection Mode Environment

/// Holds whether the budget carousel is currently in multi-select mode.
///
/// This is deliberately a reference type read via `@Observable` property tracking rather
/// than a plain `Bool` threaded through `.environment()`. An `.environment()` *value* change
/// forces SwiftUI to walk back through every intermediate view to push the new value down —
/// including MonthPageView, even though it never reads `isSelecting` itself — so toggling
/// selection would still re-run MonthPageView's whole body (calendar, totals, filtering).
/// By contrast, the environment *reference* here never changes (BudgetPageView creates one
/// instance and keeps it for the view's lifetime), so writing `.environment(\.selectionMode, ...)`
/// is a no-op from SwiftUI's diffing perspective. Only `isSelecting` mutates, and `@Observable`'s
/// per-property tracking invalidates exactly the row views that read it directly — no tree walk.
@MainActor
@Observable
final class SelectionModeModel {
    var isSelecting: Bool = false
}

extension EnvironmentValues {
    @Entry var selectionMode: SelectionModeModel = .defaultInstance
}

extension SelectionModeModel {
    static let defaultInstance = SelectionModeModel()
}

// MARK: - Add Item Type

enum AddItemType: String, CaseIterable, Codable {
    case expense = "Expense"
    case income = "Income"
    case reallocation = "Reallocation"

    var systemImage: String {
        switch self {
        case .expense: return "cart"
        case .income: return "dollarsign.circle"
        case .reallocation: return "arrow.left.arrow.right"
        }
    }
}

// MARK: - Item Type Picker Toolbar Item

/// Principal (title-replacing) type-picker Menu for add/edit sheets.
/// Matches the PageNavigationToolbarItem style used throughout the app.
struct ItemTypePickerToolbarItem: ToolbarContent {
    @Binding var itemType: AddItemType
    var types: [AddItemType]

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                ForEach(types.filter { $0 != itemType }, id: \.self) { type in
                    Button {
                        itemType = type
                    } label: {
                        Label(type.rawValue, systemImage: type.systemImage)
                    }
                }
            } label: {
                Label(itemType.rawValue, systemImage: itemType.systemImage)
                    .labelStyle(.titleOnly)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize()
            }
            .tint(.primary)
        }
    }
}

// MARK: - Keyboard Utilities

/// Programmatically dismisses the UIKit keyboard.
func resignKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Navigation Restoration Utilities

/// Applies `changes` in a transaction with animations disabled, so a state mutation that
/// would normally trigger SwiftUI's push/pop transition (e.g. flipping a `navigationDestination`
/// flag) instead lands instantly. Used when restoring saved navigation state on cold launch,
/// where there was no user tap to animate a transition for.
func withoutAnimation(_ changes: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, changes)
}

// MARK: - View Extensions

extension View {
    /// Conditionally applies a transformation to a view based on a boolean condition.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Monitors a boolean FocusState binding and trims whitespace from the text when focus is lost.
    func trimWhitespaceOnEditingEnd(_ text: Binding<String>, isFocused: FocusState<Bool>.Binding) -> some View {
        self.onChange(of: isFocused.wrappedValue) { _, newValue in
            if !newValue {
                text.wrappedValue = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Attaches the "Edit Recurring Item" scope-selection alert as a background overlay.
    /// Shared by EditExpenseView and EditIncomeView to avoid duplicating the identical alert block.
    func recurringEditAlert(
        isPresented: Binding<Bool>,
        pendingScope: Binding<RecurringScope?>,
        applyEdit: @escaping () -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert("Edit Recurring Item", isPresented: isPresented) {
                        Button("All Occurrences", role: .destructive) {
                            pendingScope.wrappedValue = .all
                            applyEdit()
                        }
                        Button("Current and Future", role: .destructive) {
                            pendingScope.wrappedValue = .currentAndFuture
                            applyEdit()
                        }
                        Button("Current Occurrence", role: .destructive) {
                            pendingScope.wrappedValue = .currentOnly
                            applyEdit()
                        }
                        Button("Cancel", role: .cancel) {
                            pendingScope.wrappedValue = nil
                        }
                    } message: {
                        Text("This is a recurring item. Choose which occurrences to update:")
                    }
            }
        }
    }
}

// MARK: - Category Renamed Observer

extension View {
    /// Listens for CategoryRenamed notifications and updates both arrays in-place.
    func onCategoryRenamed(expenses: Binding<[Expense]>, incomes: Binding<[Income]>) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .categoryRenamed)) { notification in
            guard let userInfo = notification.userInfo,
                  let oldName = userInfo["oldName"] as? String,
                  let newName = userInfo["newName"] as? String else { return }
            expenses.wrappedValue = renamingCategory(oldName, to: newName, in: expenses.wrappedValue)
            incomes.wrappedValue  = renamingCategory(oldName, to: newName, in: incomes.wrappedValue)
        }
    }

    /// Listens for CategoryDeleted notifications and removes the category from both arrays in-place.
    func onCategoryDeleted(expenses: Binding<[Expense]>, incomes: Binding<[Income]>) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .categoryDeleted)) { notification in
            guard let category = notification.userInfo?["name"] as? String else { return }
            expenses.wrappedValue = expenses.wrappedValue.map { var x = $0; x.categories.removeAll { $0 == category }; return x }
            incomes.wrappedValue  = incomes.wrappedValue.map  { var x = $0; x.categories.removeAll { $0 == category }; return x }
        }
    }
}

// MARK: - Notification Name Constants

extension Notification.Name {
    static let categoryRenamed            = Notification.Name("CategoryRenamed")
    static let categoryDeleted            = Notification.Name("CategoryDeleted")
    static let highlightBudgetOverviewRow = Notification.Name("HighlightBudgetOverviewRow")
    static let scrollPageToTop            = Notification.Name("ScrollPageToTop")
    static let scrollToNewItem            = Notification.Name("ScrollToNewItem")
    static let scrollPageToFirstSection      = Notification.Name("ScrollPageToFirstSection")
    static let scrollSheetPageToFirstSection = Notification.Name("ScrollSheetPageToFirstSection")
    static let sharedAttachmentsImported     = Notification.Name("SharedAttachmentsImported")
}

// MARK: - Destructive Delete Alert

extension View {
    /// Attaches a destructive "Delete" confirmation alert using the AlertContainer pattern.
    /// The alert title and optional message are configurable; buttons are always Delete (destructive) + Cancel.
    func destructiveDeleteAlert(
        title: String = "Delete?",
        message: String? = nil,
        isPresented: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert(title, isPresented: isPresented) {
                        Button("Delete", role: .destructive, action: onDelete)
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        if let msg = message {
                            Text(msg)
                        }
                    }
            }
        }
    }
}

// MARK: - Rename Attachment Alert

extension View {
    /// Attaches the standard "Rename Attachment" alert with text field and extension-aware save.
    /// Shared by AttachmentManagementView and BudgetAttachmentManagementView.
    func renameAttachmentAlert(
        isPresented: Binding<Bool>,
        renameText: Binding<String>,
        onSave: @escaping (String) -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert("Rename Attachment", isPresented: isPresented) {
                        TextField("File Name", text: renameText)
                            .textInputAutocapitalization(.words)
                        Button("Save") {
                            let trimmed = renameText.wrappedValue.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            onSave(trimmed)
                        }
                        Button("Cancel", role: .cancel) { isPresented.wrappedValue = false }
                    }
            }
        }
    }
}

// MARK: - Category Management Alerts

extension View {
    /// Attaches the three standard category management alerts (New / Rename / Delete)
    /// as a single modifier. Shared by CategoryPickerView and FilterOptionsSheet.
    func categoryManagementAlerts(
        newCategoryName: Binding<String>,
        showingAddAlert: Binding<Bool>,
        onAdd: @escaping () -> Void,
        editCategoryName: Binding<String>,
        showingEditAlert: Binding<Bool>,
        onRename: @escaping () -> Void,
        categoryToDelete: Binding<String?>,
        showingDeleteConfirmation: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) -> some View {
        self
            .background {
                AlertContainer {
                    Color.clear
                        .alert("New Category", isPresented: showingAddAlert) {
                            TextField("Category Name", text: newCategoryName)
                                .textInputAutocapitalization(.words)
                            Button("Add") { onAdd() }
                            Button("Cancel", role: .cancel) { }
                        }
                        .alert("Rename Category", isPresented: showingEditAlert) {
                            TextField("Category Name", text: editCategoryName)
                                .textInputAutocapitalization(.words)
                            Button("Save") { onRename() }
                            Button("Cancel", role: .cancel) { }
                        }
                        .alert("Delete Category?", isPresented: showingDeleteConfirmation) {
                            Button("Delete", role: .destructive) {
                                if categoryToDelete.wrappedValue != nil { onDelete() }
                                categoryToDelete.wrappedValue = nil
                            }
                            Button("Cancel", role: .cancel) { categoryToDelete.wrappedValue = nil }
                        }
                }
            }
    }
}

// MARK: - Safe Binding Helper

/// Utility for creating stable, identity-based bindings to elements within arrays.
/// Useful for passing bindings to SwiftUI views without risking index-based crashes.
struct SafeBindingHelper {
    /// Creates a binding to a specific array element using its identity rather than its index.
    ///
    /// - Parameters:
    ///   - item: The identifiable item to create a binding for (used to match by ID)
    ///   - array: A binding to the array containing the item
    /// - Returns: A binding to the item if it exists in the array, or `nil` if not found
    ///
    /// - Note: The getter captures the initial index but doesn't re-validate it on access,
    ///         which could be unsafe if the array is mutated between binding creation and use.
    ///         The setter safely re-validates the item's position before updating.
    static func binding<T: Identifiable>(for item: T, in array: Binding<[T]>) -> Binding<T>? where T.ID: Equatable {
        guard let index = array.wrappedValue.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }
        return Binding(
            // WARNING: The getter uses the captured index without re-validating.
            get: { array.wrappedValue[index] },
            set: { newValue in
                if let currentIndex = array.wrappedValue.firstIndex(where: { $0.id == item.id }) {
                    array.wrappedValue[currentIndex] = newValue
                }
            }
        )
    }
}
// MARK: - Spring List Scroll to Top

/// Drives scroll-to-top with a sine ease-in-out curve — symmetric deceleration suits
/// returning to the top of a list, where a gentle arrival feels natural.
private struct SpringListScrollInstaller: UIViewRepresentable {
    /// When false the page is off-screen; scroll the list to the top so it's
    /// ready when the user swipes back to it.
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { context.coordinator.probe }
    func updateUIView(_ uiView: UIView, context: Context) {
        // Page went off-screen: jump instantly — no animation needed since the user
        // can't see it, and CADisplayLink callbacks on off-screen scroll views are
        // throttled by iOS which causes the scroll to silently fail when far from top.
        if !isActive { context.coordinator.scrollToTop(animated: false) }
    }

    final class Coordinator: NSObject {
        let probe: UIView = {
            let v = UIView()
            v.backgroundColor = .clear
            v.isUserInteractionEnabled = false
            return v
        }()
        private weak var scrollView: UIScrollView?
        private var token: NSObjectProtocol?
        private var displayLink: CADisplayLink?
        private var startY: CGFloat = 0
        private var targetY: CGFloat = 0
        private var startTime: CFTimeInterval = 0
        private var duration: CFTimeInterval = 0.3

        override init() {
            super.init()
            token = NotificationCenter.default.addObserver(
                forName: .scrollPageToTop, object: nil, queue: .main
            ) { [weak self] _ in self?.scrollToTop(animated: true) }
            DispatchQueue.main.async { [weak self] in self?.install() }
        }

        deinit {
            displayLink?.invalidate()
            if let token { NotificationCenter.default.removeObserver(token) }
        }

        func scrollToTop(animated: Bool) {
            if scrollView == nil { install() }
            guard let sv = scrollView else { return }
            let target = -sv.adjustedContentInset.top
            guard sv.contentOffset.y > target else { return }
            displayLink?.invalidate()
            displayLink = nil
            guard animated else {
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: target), animated: false)
                return
            }
            startY = sv.contentOffset.y
            targetY = target
            duration = 0.35
            startTime = CACurrentMediaTime()
            sv.setContentOffset(sv.contentOffset, animated: false)
            displayLink = CADisplayLink(target: self, selector: #selector(step))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            displayLink?.add(to: .main, forMode: .common)
        }

        @objc private func step() {
            guard let sv = scrollView else { stop(); return }
            let t = min((CACurrentMediaTime() - startTime) / duration, 1.0)
            let eased = (1.0 - cos(.pi * t)) / 2.0
            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: startY + (targetY - startY) * eased), animated: false)
            if t >= 1.0 { stop() }
        }

        private func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func install() {
            var view: UIView? = probe
            while let parent = view?.superview {
                // UITableView (iOS 15-) or UICollectionView (iOS 16–26) backed List.
                if parent is UITableView || parent is UICollectionView {
                    scrollView = parent as? UIScrollView
                    return
                }
                view = parent
            }
            // Fallback: iOS 27+ may back List with a plain UIScrollView. Walking up from the
            // probe (inside the List) finds the List's scroll view before the horizontal
            // carousel's, so taking the first UIScrollView encountered is safe. If we
            // accidentally land on the carousel, startAnimation()'s guard (contentOffset.y
            // must be > target) exits harmlessly since the carousel only scrolls horizontally.
            view = probe
            while let parent = view?.superview {
                if let sv = parent as? UIScrollView {
                    scrollView = sv
                    return
                }
                view = parent
            }
        }
    }
}

extension View {
    func springListScrollToTop(isActive: Bool = true) -> some View {
        background(SpringListScrollInstaller(isActive: isActive))
    }
}

// MARK: - Carousel Ease-Out Scroll Driver

/// Drives the horizontal carousel's programmatic page jumps frame-by-frame via
/// CADisplayLink + setContentOffset(_:animated:false), giving a consistent sine
/// ease-in-out regardless of jump distance without relying on SwiftUI's animation system.
///
/// Plain class (not ObservableObject) — animation state is surfaced to SwiftUI via
/// the @State var isCarouselAnimating in BudgetPageView, avoiding extra view re-renders
/// that @Published would trigger and which interfered with onChange item-tracking logic.
final class CarouselJumpDriver {
    weak var scrollView: UIScrollView?

    /// Called by CarouselScrollFinder's coordinator when the user begins a horizontal drag.
    /// The owner (BudgetPageView / FilterAndTypeSheet) assigns this closure and applies
    /// its own isJumpAnimating / isCarouselAnimating guards before posting the reset notification.
    var onUserDragBegan: (() -> Void)?

    /// True while animate(toX:) is running. Checked by the pan coordinator so the
    /// drag-start reset is suppressed during programmatic jumps.
    private(set) var isAnimating = false

    private var displayLink: CADisplayLink?
    private var startX: CGFloat = 0
    private var targetX: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    private var animDuration: CFTimeInterval = 0.4
    private var completion: (() -> Void)?

    // Companion snapshot driven frame-for-frame alongside the scroll animation.
    // Both travel the same distance with the same curve, so they stay perfectly in sync.
    private weak var companionView: UIView?
    private var companionFromTx: CGFloat = 0
    private var companionToTx: CGFloat = 0

    func animate(toX targetX: CGFloat, duration: CFTimeInterval,
                 companion: (view: UIView, fromTx: CGFloat, toTx: CGFloat)? = nil,
                 completion: @escaping () -> Void) {
        guard let sv = scrollView else { completion(); return }
        let clampedTarget = max(0, min(targetX, sv.contentSize.width - sv.bounds.width))
        guard abs(sv.contentOffset.x - clampedTarget) > 0.5 else { completion(); return }

        isAnimating = true
        self.startX = sv.contentOffset.x
        self.targetX = clampedTarget
        self.startTime = CACurrentMediaTime()
        self.animDuration = duration
        self.completion = completion
        self.companionView = companion?.view
        self.companionFromTx = companion?.fromTx ?? 0
        self.companionToTx = companion?.toTx ?? 0

        sv.setContentOffset(sv.contentOffset, animated: false)  // cancel momentum
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(step))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
    }

    /// Critically-damped spring position curve. Starts at 0 with zero velocity,
    /// settles exactly at 1 — natural deceleration with no overshoot.
    /// w controls stiffness (higher = snappier settle).
    private static func springEase(_ t: CGFloat) -> CGFloat {
        let w: CGFloat = 8
        let raw = 1 - (1 + w * t) * exp(-w * t)
        let norm = 1 - (1 + w) * exp(-w)
        return raw / norm
    }

    @objc private func step() {
        guard let sv = scrollView else { finish(); return }
        let t = min((CACurrentMediaTime() - startTime) / animDuration, 1.0)
        let eased = Self.springEase(CGFloat(t))
        let x = startX + (targetX - startX) * eased
        sv.setContentOffset(CGPoint(x: x, y: sv.contentOffset.y), animated: false)
        if let companion = companionView {
            let tx = companionFromTx + (companionToTx - companionFromTx) * eased
            companion.transform = CGAffineTransform(translationX: tx, y: 0)
        }
        if t >= 1.0 { finish() }
    }

    private func finish() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        companionView?.removeFromSuperview()
        companionView = nil
        let cb = completion
        completion = nil
        cb?()
    }
}

/// Background this on the LazyHStack (not on individual pages) to locate the
/// backing UIScrollView and hand it to the CarouselJumpDriver.
struct CarouselScrollFinder: UIViewRepresentable {
    let driver: CarouselJumpDriver

    func makeCoordinator() -> Coordinator { Coordinator(driver: driver) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            Self.findAndWire(from: v, driver: driver, coordinator: context.coordinator)
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Retry on every update until found — handles sheets and other contexts
        // where the async in makeUIView fires before the view is in the hierarchy.
        if driver.scrollView == nil {
            Self.findAndWire(from: uiView, driver: driver, coordinator: context.coordinator)
        }
    }

    private static func findAndWire(from view: UIView, driver: CarouselJumpDriver, coordinator: Coordinator) {
        var v: UIView? = view
        while let parent = v?.superview {
            if let sv = parent as? UIScrollView {
                driver.scrollView = sv
                coordinator.attach(to: sv)
                return
            }
            v = parent
        }
    }

    /// Adds a pan-gesture target-action to the backing UIScrollView so we detect
    /// when the user starts dragging horizontally (before the swipe settles).
    final class Coordinator: NSObject {
        private weak var driver: CarouselJumpDriver?
        private var didAttach = false

        init(driver: CarouselJumpDriver) { self.driver = driver }

        func attach(to scrollView: UIScrollView) {
            guard !didAttach else { return }
            didAttach = true
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        }

        @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
            guard gr.state == .began else { return }
            driver?.onUserDragBegan?()
        }
    }
}

