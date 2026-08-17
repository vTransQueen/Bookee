//
//  ItemRowViews.swift
//  Bookee
//
//  Reusable row views for displaying books in lists.
//

import SwiftUI

// MARK: - Selection Indicator

/// Reusable checkmark/circle indicator for list rows in selection mode.
struct SelectionIndicator: View {
    let isSelected: Bool
    var highlightColor: Color = .blue

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? highlightColor : .gray)
            .imageScale(.large)
    }
}

// MARK: - Book Row View

/// A reusable row view for displaying a book in the library list.
struct BookRowView: View {
    let book: Book
    let isSelecting: Bool
    let isSelected: Bool
    let dateFormat: DateFormat
    let highlightColor: Color
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(.trailing, 12)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(book.seriesName.map { "\($0): \(book.displayTitle)" } ?? book.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(book.author.isEmpty ? "Unknown Author" : book.author)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        if let number = book.seriesNumber {
                            Image(systemName: "books.vertical")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let total = book.seriesTotalCount {
                                Text("Book \(number)/\(total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Book \(number)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        if let format = book.bookFormat {
                            Image(systemName: format.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(format.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let ownership = book.ownership {
                            Image(systemName: ownership.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ownership.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: book.status.icon)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                        Text(book.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(statusColor)

                        if let rating = book.rating, rating > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(rating)/5 Stars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "star")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Unrated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .animation(nil, value: isSelecting)
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { onToggleSelection() } else { onEdit() }
        }
        .if(!isSelecting) { view in
            view
                .contextMenu {
                    Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Divider()
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(action: onDelete) { Image(systemName: "trash") }.tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }.tint(.blue)
                }
        }
    }

    private var statusColor: Color {
        switch book.status {
        case .toRead: return .secondary
        case .reading: return .blue
        case .finished: return .green
        case .dnf: return .red
        }
    }

}
