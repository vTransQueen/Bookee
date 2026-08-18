//
//  FilterOptionsSheet.swift
//  Bookee
//
//  Filter sheet for the main library — lets the user narrow books by status, genre, and rating.
//

import SwiftUI

struct FilterOptionsSheet: View {
    @Binding var filterStatus: ReadingStatus?
    @Binding var filterGenre: String?
    @Binding var filterRating: Int?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("genres") private var storedGenres: String = "[]"
    @AppStorage("showFooters") private var showFooters: Bool = true
    @HighlightColorStorage private var highlightColor

    private var genres: [String] { storedGenres.asStringList }

    private var isFiltering: Bool {
        filterStatus != nil || filterGenre != nil || filterRating != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                if !genres.isEmpty {
                    genreSection
                }
                ratingSection
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        filterStatus = nil
                        filterGenre = nil
                        filterRating = nil
                    } label: { Label("Reset", systemImage: "xmark") }
                    .tint(.red)
                    .disabled(!isFiltering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }
                        .tint(.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            filterRow(
                label: "All",
                isSelected: filterStatus == nil,
                action: { filterStatus = nil }
            )
            ForEach(ReadingStatus.allCases, id: \.self) { status in
                filterRow(
                    label: status.rawValue,

                    isSelected: filterStatus == status,
                    action: { filterStatus = filterStatus == status ? nil : status }
                )
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: - Genre

    private var genreSection: some View {
        Section {
            filterRow(
                label: "All Genres",
                isSelected: filterGenre == nil,
                action: { filterGenre = nil }
            )
            ForEach(genres, id: \.self) { genre in
                filterRow(
                    label: genre,
                    isSelected: filterGenre == genre,
                    action: { filterGenre = filterGenre == genre ? nil : genre }
                )
            }
        } header: {
            Text("Genre")
        }
    }

    // MARK: - Rating

    private var ratingSection: some View {
        Section {
            filterRow(
                label: "Any Rating",
                isSelected: filterRating == nil,
                action: { filterRating = nil }
            )
            ForEach(1...5, id: \.self) { stars in
                Button {
                    filterRating = filterRating == stars ? nil : stars
                } label: {
                    HStack {
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= stars ? "star.fill" : "star")
                                    .foregroundStyle(star <= stars ? highlightColor : .secondary)
                            }
                        }
                        Spacer()
                        if filterRating == stars {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(highlightColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        } header: {
            Text("Rating")
        }
    }

    // MARK: - Row Helper

    @ViewBuilder
    private func filterRow(label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                Text(label)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(highlightColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
