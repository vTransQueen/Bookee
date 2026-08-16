//
//  SharedComponents.swift
//  Bookee
//
//  Shared view components and helpers used across multiple views.
//

import SwiftUI

// MARK: - Alert Container

/// Wraps content and applies primary tint so alerts stay neutral regardless of any custom highlight color.
struct AlertContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.tint(.primary)
    }
}

// MARK: - Empty State Placeholder

/// Reusable empty-state view with an icon, title, and optional message.
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

// MARK: - Alphabet Scroller

/// A vertical strip of letter buttons used as an index scroller alongside an alphabetically-sorted list.
/// Attach it as an overlay and call `onSelect` to drive `ScrollViewReader.scrollTo`.
struct AlphabetScroller: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var isDragging = false
    private let itemHeight: CGFloat = 16
    private let itemSpacing: CGFloat = 2

    var body: some View {
        VStack(spacing: itemSpacing) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: itemHeight)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background {
            if isDragging {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    isDragging = true
                    let offsetY = max(0, value.location.y - 6)
                    let index = Int(offsetY / (itemHeight + itemSpacing))
                    let clamped = max(0, min(letters.count - 1, index))
                    onSelect(letters[clamped])
                }
                .onEnded { _ in isDragging = false }
        )
    }
}

// MARK: - Selection Mode Toolbar

/// ToolbarContent for selection mode: Select All / Deselect All on the trailing side
/// and a Delete button on the bottom bar.
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
