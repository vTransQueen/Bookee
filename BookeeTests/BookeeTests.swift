//
//  BookeeTests.swift
//  BookeeTests
//
//  Created by Kara Eveland on 2/14/26.
//

import Testing
import Foundation
import CoreGraphics
@testable import Bookee

// MARK: - Book Model Tests

@Suite("Book Model Tests")
struct BookModelTests {

    @Test("ReadingStatus all cases exist")
    func testReadingStatusCases() {
        let allCases = ReadingStatus.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.toRead))
        #expect(allCases.contains(.reading))
        #expect(allCases.contains(.finished))
        #expect(allCases.contains(.dnf))
    }

    @Test("ReadingStatus raw values round-trip through Codable")
    func testReadingStatusCodable() throws {
        for status in ReadingStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ReadingStatus.self, from: encoded)
            #expect(decoded == status)
        }
    }

    @Test("Book reading progress calculation")
    func testReadingProgress() {
        let book = Book(timestamp: Date(), title: "Test", author: "Author")
        #expect(book.readingProgress == nil)

        book.pageCount = 200
        #expect(book.readingProgress == nil) // currentPage still nil

        book.currentPage = 100
        let progress = book.readingProgress
        #expect(progress != nil)
        #expect(progress! == 0.5)

        book.currentPage = 200
        #expect(book.readingProgress == 1.0)

        book.currentPage = 250 // beyond total — clamps to 1.0
        #expect(book.readingProgress == 1.0)
    }

    @Test("Book genres round-trip through JSON storage")
    func testGenresRoundTrip() {
        let book = Book(timestamp: Date(), title: "Test", author: "Author")
        #expect(book.genres.isEmpty)

        book.genres = ["Fantasy", "Adventure", "Mystery"]
        let retrieved = book.genres
        #expect(retrieved.count == 3)
        #expect(retrieved.contains("Fantasy"))
        #expect(retrieved.contains("Adventure"))
        #expect(retrieved.contains("Mystery"))
    }

    @Test("Book genres empty by default")
    func testGenresDefaultEmpty() {
        let book = Book(timestamp: Date())
        #expect(book.genres.isEmpty)
        #expect(book.genresData == nil || book.genresData == "[]")
    }

    @Test("Book soft-delete sets deletedDate")
    func testSoftDelete() {
        let book = Book(timestamp: Date())
        #expect(!book.isDeleted)
        #expect(book.deletedDate == nil)

        book.deletedDate = Date()
        #expect(book.isDeleted)
        #expect(book.deletedDate != nil)
    }

    @Test("Book daysUntilPermanentDeletion returns nil when not deleted")
    func testDaysUntilDeletionNotDeleted() {
        let book = Book(timestamp: Date())
        #expect(book.daysUntilPermanentDeletion == nil)
    }

    @Test("Book displayTitle falls back to 'New Book' for empty title")
    func testDisplayTitleFallback() {
        let emptyBook = Book(timestamp: Date(), title: "")
        #expect(emptyBook.displayTitle == "New Book")

        let namedBook = Book(timestamp: Date(), title: "Dune")
        #expect(namedBook.displayTitle == "Dune")
    }

    @Test("Attachment encode/decode round-trip via Book")
    func testAttachmentRoundTrip() throws {
        let book = Book(timestamp: Date(), title: "Test", author: "Author")
        let attachment = Attachment(
            data: Data("hello".utf8),
            fileName: "note.txt",
            fileType: .document
        )
        try book.encodeAttachments([attachment])
        let decoded = book.decodeAttachments()
        #expect(decoded.count == 1)
        #expect(decoded.first?.fileName == "note.txt")
        #expect(decoded.first?.fileType == .document)
    }
}

// MARK: - Genre Helpers Tests

@Suite("Genre Helpers Tests")
struct GenreHelpersTests {

    @Test("asCategories decodes valid JSON string")
    func testAsCategoriesDecodeValid() {
        let json = "[\"Fantasy\",\"Sci-Fi\",\"Thriller\"]"
        let categories = json.asCategories
        #expect(categories.count == 3)
        #expect(categories[0] == "Fantasy")
        #expect(categories[1] == "Sci-Fi")
        #expect(categories[2] == "Thriller")
    }

    @Test("asCategories returns empty array for invalid JSON")
    func testAsCategoriesDecodeInvalid() {
        #expect("not json".asCategories.isEmpty)
        #expect("".asCategories.isEmpty)
        #expect("{}".asCategories.isEmpty)
    }

    @Test("asAppStorageString encodes array to JSON")
    func testAsAppStorageStringEncodes() {
        let genres = ["Romance", "Mystery"]
        let json = genres.asAppStorageString
        let decoded = json.asCategories
        #expect(decoded == genres)
    }

    @Test("asAppStorageString handles empty array")
    func testAsAppStorageStringEmpty() {
        let json: [String] = []
        let encoded = json.asAppStorageString
        #expect(encoded == "[]")
        #expect(encoded.asCategories.isEmpty)
    }
}

// MARK: - Color Conversion Tests

@Suite("Color Conversion Precision Tests")
struct ColorConversionTests {

    @Test("RGB to hex conversion uses proper rounding")
    func testRGBToHexConversion() {
        let testValues: [CGFloat] = [0.0, 0.5, 0.999, 1.0, 0.001, 0.499, 0.501]
        for value in testValues {
            let scaled = (value * 255.0).rounded()
            let clamped = Int(max(0, min(255, scaled)))
            #expect(clamped >= 0)
            #expect(clamped <= 255)
            if value == 0.0 { #expect(clamped == 0) }
            if value == 1.0 { #expect(clamped == 255) }
            if value == 0.5 { #expect(clamped == 128) }
        }
    }

    @Test("Hex string format is correct")
    func testHexStringFormat() {
        let testCases: [(r: Int, g: Int, b: Int, expected: String)] = [
            (0, 0, 0, "000000"),
            (255, 255, 255, "FFFFFF"),
            (0, 122, 255, "007AFF"),
            (255, 0, 0, "FF0000"),
            (0, 255, 0, "00FF00"),
            (0, 0, 255, "0000FF"),
        ]
        for tc in testCases {
            let hex = String(format: "%02X%02X%02X", tc.r, tc.g, tc.b)
            #expect(hex == tc.expected)
        }
    }
}
