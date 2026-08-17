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
                coverThumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.seriesName.map { "\($0): \(book.displayTitle)" } ?? book.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(book.author.isEmpty ? "Unknown Author" : book.author)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Text("•").font(.caption).foregroundStyle(.secondary)
                        if let number = book.seriesNumber {
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
                            Text(format.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("•").font(.caption).foregroundStyle(.secondary)
                        }

                        if let ownership = book.ownership {
                            Text(ownership.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("•").font(.caption).foregroundStyle(.secondary)
                        }

                        Text(book.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(statusColor)

                        Text("•").font(.caption).foregroundStyle(.secondary)
                        if let rating = book.rating, rating > 0 {
                            Text("\(rating)/5 Stars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
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

    private var coverThumbnail: some View {
        Group {
            if let coverData = book.coverImageData, let uiImage = UIImage(data: coverData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 67)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 48, height: 67)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}
