//
//  Models.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import Foundation
import SwiftData

// MARK: - Reading Status

enum ReadingStatus: String, Codable, CaseIterable {
    case toRead = "Unread"
    case reading = "Started"
    case finished = "Finished"
    case dnf = "Stopped"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "To Read": self = .toRead
        case "Finished": self = .finished
        case "Did Not Finish", "Not Finished": self = .dnf
        default: self = ReadingStatus(rawValue: raw) ?? .toRead
        }
    }

    var icon: String {
        switch self {
        case .toRead: return "books.vertical"
        case .reading: return "book"
        case .finished: return "book.closed"
        case .dnf: return "bookmark"
        }
    }
}

// MARK: - Book Ownership

enum BookOwnership: String, Codable, CaseIterable {
    case rented = "Rented"
    case purchased = "Owned"
    case borrowed = "Borrowed"
    case unowned = "Unowned"

    var icon: String {
        switch self {
        case .purchased: return "bag"
        case .borrowed: return "person.2"
        case .rented: return "clock.arrow.circlepath"
        case .unowned: return "xmark.circle"
        }
    }
}

// MARK: - Book Format

enum BookFormat: String, Codable, CaseIterable {
    case paperback = "Paper"
    case audiobook = "Audio"
    case ebook = "eBook"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "Paperback" { self = .paperback }
        else if raw == "Audiobook" { self = .audiobook }
        else { self = BookFormat(rawValue: raw) ?? .paperback }
    }

    var icon: String {
        switch self {
        case .ebook: return "ipad"
        case .paperback: return "book.pages"
        case .audiobook: return "headphones"
        }
    }
}

// MARK: - Book Model

@Model
final class Book {
    /// Creation timestamp; serves as a stable unique identity for navigation-state restore.
    var timestamp: Date
    var lastModifiedDate: Date
    var title: String
    var author: String
    var manualSortOrder: Int
    var status: ReadingStatus
    var rating: Int?            // 0...5, nil = unrated
    /// JSON-encoded [String] of user-defined genres.
    var genresData: String?
    /// JSON-encoded [String] of user-defined locations.
    var locationsData: String?
    var notes: String?
    @Attribute(originalName: "ownership")
    var ownershipRaw: String?
    var ownership: BookOwnership? {
        get { ownershipRaw.flatMap(BookOwnership.init(rawValue:)) }
        set { ownershipRaw = newValue?.rawValue }
    }

    @Attribute(originalName: "bookFormat")
    var bookFormatRaw: String?
    var bookFormat: BookFormat? {
        get { bookFormatRaw.flatMap(BookFormat.init(rawValue:)) }
        set { bookFormatRaw = newValue?.rawValue }
    }
    var seriesName: String?
    var seriesNumber: Int?
    var seriesTotalCount: Int?
    /// Non-nil when soft-deleted; items in Trash are permanently removed after 30 days.
    var deletedDate: Date?

    @Attribute(.externalStorage) var coverImageData: Data?
    /// JSON-encoded [Attachment] for extra photos/PDFs attached to this book.
    @Attribute(.externalStorage) var attachmentsData: Data?

    @Transient var isUnsavedDuplicate: Bool = false

    init(
        timestamp: Date,
        title: String = "",
        author: String = "",
        manualSortOrder: Int = 0,
        status: ReadingStatus = .toRead
    ) {
        self.timestamp = timestamp
        self.lastModifiedDate = timestamp
        self.title = title
        self.author = author
        self.manualSortOrder = manualSortOrder
        self.status = status
        self.deletedDate = nil
    }

    var displayTitle: String { title.isEmpty ? "New Book" : title }

    var isDeleted: Bool { deletedDate != nil }

    var daysUntilPermanentDeletion: Int? {
        guard let deletedDate else { return nil }
        let daysSinceDeletion = Calendar.current.dateComponents([.day], from: deletedDate, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }

    var genres: [String] {
        get {
            guard let genresData,
                  let data = genresData.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let string = String(data: data, encoding: .utf8) else { return }
            genresData = string
        }
    }

    var locations: [String] {
        get {
            guard let locationsData,
                  let data = locationsData.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let string = String(data: data, encoding: .utf8) else { return }
            locationsData = string
        }
    }

    func decodeAttachments() -> [Attachment] {
        guard let attachmentsData else { return [] }
        return (try? JSONDecoder().decode([Attachment].self, from: attachmentsData)) ?? []
    }

    func encodeAttachments(_ attachments: [Attachment]) throws {
        attachmentsData = try JSONEncoder().encode(attachments)
    }
}

// MARK: - Attachment Type

enum AttachmentType: String, Codable {
    case image
    case pdf
    case document
    case other

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF"
        case .document: return "Document"
        case .other: return "File"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.fill"
        case .document: return "doc.text.fill"
        case .other: return "doc"
        }
    }

    static func fromUTType(_ utType: String) -> AttachmentType {
        if utType.hasPrefix("image") {
            return .image
        } else if utType.contains("pdf") {
            return .pdf
        } else if utType.contains("text") || utType.contains("document") {
            return .document
        } else {
            return .other
        }
    }
}

// MARK: - Attachment Model

struct Attachment: Identifiable, Equatable, Codable {
    let id: UUID
    var data: Data
    var fileName: String
    var fileType: AttachmentType
    var dateAdded: Date

    init(id: UUID = UUID(), data: Data, fileName: String, fileType: AttachmentType, dateAdded: Date = Date()) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.fileType = fileType
        self.dateAdded = dateAdded
    }

}
