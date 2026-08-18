//
//  BackupManager.swift
//  Bookee
//
//  Created by Kara Eveland on 2/25/26.
//

import Foundation
import SwiftData

// MARK: - Backup Data Structures

/// Flat mirror of Book for JSON backup storage.
struct BackupBook: Codable, Equatable {
    let timestamp: Date
    let lastModifiedDate: Date
    let title: String
    let author: String
    let manualSortOrder: Int
    let status: String
    let rating: Int?
    let genresData: String?
    let notes: String?
    let deletedDate: Date?
    let attachmentsData: Data?
    let coverImageData: Data?

    static func == (lhs: BackupBook, rhs: BackupBook) -> Bool {
        lhs.timestamp == rhs.timestamp &&
        lhs.lastModifiedDate == rhs.lastModifiedDate &&
        lhs.title == rhs.title &&
        lhs.author == rhs.author &&
        lhs.manualSortOrder == rhs.manualSortOrder &&
        lhs.status == rhs.status &&
        lhs.rating == rhs.rating &&
        lhs.genresData == rhs.genresData &&
        lhs.notes == rhs.notes &&
        lhs.deletedDate == rhs.deletedDate &&
        lhs.attachmentsData == rhs.attachmentsData &&
        lhs.coverImageData == rhs.coverImageData
    }
}

/// App-level settings snapshot included in each backup.
struct BackupAppSettings: Codable {
    let appearanceMode: String?
    let dateFormat: String?  // retained for decoding legacy backup files
    let sortOrder: String?
    let userName: String?
    let highlightColorHex: String?
    let genres: String?
    let automaticBackupsEnabled: Bool?
    let maxBackupsToKeep: Int?
    let showFooters: Bool?
}

/// Complete backup snapshot with metadata.
struct Backup: Codable, Identifiable {
    let id: UUID
    let date: Date
    let bookCount: Int
    let books: [BackupBook]
    let appSettings: BackupAppSettings?

    /// Preserves the on-disk JSON keys ("itemCount", "items") so existing backup files continue to decode.
    enum CodingKeys: String, CodingKey {
        case id, date
        case bookCount = "itemCount"
        case books = "items"
        case appSettings
    }

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Backup Manager

/// Manages automatic and manual backups of app data to the local file system.
class BackupManager {
    static let shared = BackupManager()

    private let backupDirectory: URL

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        backupDirectory = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        print("📂 Backup directory: \(backupDirectory.path)")
    }

    private var maxBackups: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxBackupsToKeep")
        return stored != 0 ? stored : 5
    }

    // MARK: - Create Backup

    func createBackup(books: [Book], force: Bool = false) {
        do {
            let backupBooks = books.map { book in
                BackupBook(
                    timestamp: book.timestamp,
                    lastModifiedDate: book.lastModifiedDate,
                    title: book.title,
                    author: book.author,
                    manualSortOrder: book.manualSortOrder,
                    status: book.status.rawValue,
                    rating: book.rating,
                    genresData: book.genresData,
                    notes: book.notes,
                    deletedDate: book.deletedDate,
                    attachmentsData: book.attachmentsData,
                    coverImageData: book.coverImageData
                )
            }

            if !force && !hasDataChanged(newBackupBooks: backupBooks) {
                print("⏭️ Skipping backup - no data changes detected")
                return
            }

            let ud = UserDefaults.standard
            let settings = BackupAppSettings(
                appearanceMode: ud.string(forKey: "appearanceMode"),
                dateFormat: nil,
                sortOrder: ud.string(forKey: "sortOrder"),
                userName: ud.string(forKey: "userName"),
                highlightColorHex: ud.string(forKey: "highlightColorHex"),
                genres: ud.string(forKey: "genres"),
                automaticBackupsEnabled: ud.object(forKey: "automaticBackupsEnabled") != nil ? ud.bool(forKey: "automaticBackupsEnabled") : nil,
                maxBackupsToKeep: ud.object(forKey: "maxBackupsToKeep") != nil ? ud.integer(forKey: "maxBackupsToKeep") : nil,
                showFooters: ud.object(forKey: "showFooters") != nil ? ud.bool(forKey: "showFooters") : nil
            )

            let backup = Backup(
                id: UUID(),
                date: Date(),
                bookCount: books.count,
                books: backupBooks,
                appSettings: settings
            )

            let filename = "backup_\(backup.id.uuidString).json"
            let fileURL = backupDirectory.appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            try data.write(to: fileURL)

            print("✅ Backup created: \(backup.displayName) with \(books.count) book(s)")
            cleanupOldBackups()

        } catch {
            print("❌ Failed to create backup: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Backups

    func loadBackups() -> [Backup] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var backups: [Backup] = []

            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let backup = try decoder.decode(Backup.self, from: data)
                    backups.append(backup)
                } catch {
                    print("⚠️ Failed to load backup from \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            backups.sort { $0.date > $1.date }
            print("📂 Loaded \(backups.count) backup(s)")
            return backups

        } catch {
            print("❌ Failed to load backups: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Restore Backup

    func restoreBackup(_ backup: Backup, to modelContext: ModelContext) throws {
        print("🔄 Starting backup restoration...")

        let fetchDescriptor = FetchDescriptor<Book>()
        let existingBooks = try modelContext.fetch(fetchDescriptor)

        print("🗑️ Deleting \(existingBooks.count) existing book(s)")
        for book in existingBooks {
            modelContext.delete(book)
        }
        try modelContext.save()

        var restoredCount = 0

        for backupBook in backup.books {
            let book = Book(
                timestamp: backupBook.timestamp,
                title: backupBook.title,
                author: backupBook.author,
                manualSortOrder: backupBook.manualSortOrder,
                status: ReadingStatus(rawValue: backupBook.status) ?? .toRead
            )
            book.lastModifiedDate = backupBook.lastModifiedDate
            book.rating = backupBook.rating
            book.genresData = backupBook.genresData
            book.notes = backupBook.notes
            book.deletedDate = backupBook.deletedDate
            book.attachmentsData = validateOrClear(
                backupBook.attachmentsData,
                as: [Attachment].self,
                label: "attachments",
                itemName: backupBook.title
            )
            book.coverImageData = backupBook.coverImageData

            modelContext.insert(book)
            restoredCount += 1
            print("✅ Restored book '\(backupBook.title)'")
        }

        try modelContext.save()
        print("💾 BackupManager: Restored \(restoredCount) book(s) from backup")

        if let settings = backup.appSettings {
            let ud = UserDefaults.standard
            if let v = settings.appearanceMode        { ud.set(v, forKey: "appearanceMode") }
            if let v = settings.sortOrder             { ud.set(v, forKey: "sortOrder") }
            if let v = settings.userName              { ud.set(v, forKey: "userName") }
            if let v = settings.highlightColorHex     { ud.set(v, forKey: "highlightColorHex") }
            if let v = settings.genres                { ud.set(v, forKey: "genres") }
            if let v = settings.automaticBackupsEnabled { ud.set(v, forKey: "automaticBackupsEnabled") }
            if let v = settings.maxBackupsToKeep      { ud.set(v, forKey: "maxBackupsToKeep") }
            if let v = settings.showFooters           { ud.set(v, forKey: "showFooters") }
            print("✅ App settings restored from backup")
        }

        print("✅ Backup restoration complete: \(restoredCount) book(s) restored")
    }

    // MARK: - Delete Backup

    func deleteBackup(_ backup: Backup) {
        let filename = "backup_\(backup.id.uuidString).json"
        let fileURL = backupDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("🗑️ Deleted backup: \(backup.displayName)")
        } catch {
            print("❌ Failed to delete backup: \(error.localizedDescription)")
        }
    }

    // MARK: - Validate Backup

    func validateBackup(_ backup: Backup) -> (valid: Int, corrupted: Int, details: [String]) {
        var validItems = 0, corruptedItems = 0
        var corruptedDetails: [String] = []
        for book in backup.books {
            if let d = book.attachmentsData, !validateJSONData(d, as: [Attachment].self) {
                corruptedItems += 1
                let name = book.title.isEmpty ? "Untitled" : book.title
                corruptedDetails.append("\(name): corrupted attachments")
            } else {
                validItems += 1
            }
        }
        return (validItems, corruptedItems, corruptedDetails)
    }

    // MARK: - Cleanup

    private func validateOrClear<T: Decodable>(_ data: Data?, as type: T.Type, label: String, itemName: String) -> Data? {
        guard let data else { return nil }
        if validateJSONData(data, as: type) { return data }
        print("⚠️ Corrupted \(label) data for '\(itemName)' - will be cleared")
        return nil
    }

    private func validateJSONData<T: Decodable>(_ data: Data, as type: T.Type) -> Bool {
        (try? JSONDecoder().decode(type, from: data)) != nil
    }

    private func hasDataChanged(newBackupBooks: [BackupBook]) -> Bool {
        let existingBackups = loadBackups()
        guard let mostRecentBackup = existingBackups.first else { return true }
        if newBackupBooks.count != mostRecentBackup.books.count { return true }
        let sortedNew = newBackupBooks.sorted { $0.timestamp < $1.timestamp }
        let sortedOld = mostRecentBackup.books.sorted { $0.timestamp < $1.timestamp }
        for (new, old) in zip(sortedNew, sortedOld) {
            if new != old { return true }
        }
        return false
    }

    func cleanupOldBackups(keepingMax: Int? = nil) {
        let backups = loadBackups()
        let limit = keepingMax ?? maxBackups
        if backups.count > limit {
            let toDelete = backups.suffix(from: limit)
            for backup in toDelete { deleteBackup(backup) }
            print("🧹 Cleaned up \(toDelete.count) old backup(s), keeping \(limit)")
        }
    }
}
