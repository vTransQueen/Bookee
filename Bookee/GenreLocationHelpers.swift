//
//  GenreLocationHelpers.swift
//  Bookee
//
//  Genre helpers for managing genres across all books.
//

import SwiftUI
import SwiftData

// MARK: - Genre Rename/Delete Helpers

/// Renames a genre in every book's genres array and persists the changes.
func updateBooksForRenamedGenre(from oldName: String, to newName: String, modelContext: ModelContext) {
    let descriptor = FetchDescriptor<Book>()
    guard let books = try? modelContext.fetch(descriptor) else { return }
    var changed = false
    for book in books {
        let current = book.genres
        if current.contains(oldName) {
            book.genres = current.map { $0 == oldName ? newName : $0 }
            changed = true
        }
    }
    if changed {
        modelContext.saveWithLogging("Renamed genre '\(oldName)' → '\(newName)'")
    }
}

/// Removes a genre from every book's genres array and persists the changes.
func updateBooksForDeletedGenre(_ genre: String, modelContext: ModelContext) {
    let descriptor = FetchDescriptor<Book>()
    guard let books = try? modelContext.fetch(descriptor) else { return }
    var changed = false
    for book in books {
        let current = book.genres
        if current.contains(genre) {
            book.genres = current.filter { $0 != genre }
            changed = true
        }
    }
    if changed {
        modelContext.saveWithLogging("Removed genre '\(genre)' from books")
    }
}

/// Renames a location in every book's locations array and persists the changes.
func updateBooksForRenamedLocation(from oldName: String, to newName: String, modelContext: ModelContext) {
    let descriptor = FetchDescriptor<Book>()
    guard let books = try? modelContext.fetch(descriptor) else { return }
    var changed = false
    for book in books {
        let current = book.locations
        if current.contains(oldName) {
            book.locations = current.map { $0 == oldName ? newName : $0 }
            changed = true
        }
    }
    if changed {
        modelContext.saveWithLogging("Renamed location '\(oldName)' → '\(newName)'")
    }
}

/// Removes a location from every book's locations array and persists the changes.
func updateBooksForDeletedLocation(_ location: String, modelContext: ModelContext) {
    let descriptor = FetchDescriptor<Book>()
    guard let books = try? modelContext.fetch(descriptor) else { return }
    var changed = false
    for book in books {
        let current = book.locations
        if current.contains(location) {
            book.locations = current.filter { $0 != location }
            changed = true
        }
    }
    if changed {
        modelContext.saveWithLogging("Removed location '\(location)' from books")
    }
}

/// Returns a dictionary mapping each genre name to the number of non-deleted books that have it.
func buildGenreCounts(modelContext: ModelContext) -> [String: Int] {
    let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.deletedDate == nil })
    guard let books = try? modelContext.fetch(descriptor) else { return [:] }
    var counts: [String: Int] = [:]
    for book in books {
        for genre in book.genres {
            counts[genre, default: 0] += 1
        }
    }
    return counts
}
