//
//  DateUtilities.swift
//  Bookee
//
//  Created by Kara Eveland on 5/6/26.
//

import Foundation

// MARK: - Date Utilities

extension Date {
    var day: Int   { Calendar.current.component(.day,   from: self) }
    var month: Int { Calendar.current.component(.month, from: self) }
    var year: Int  { Calendar.current.component(.year,  from: self) }
}

// MARK: - Timestamp Helper

/// Returns the current date formatted as "yyyy-MM-dd_HH-mm-ss" — used for photo and backup filenames.
func makeTimestamp(from date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter.string(from: date)
}

// MARK: - Photo Filename Helper

func makePhotoFileName() -> String {
    "photo_\(makeTimestamp()).jpg"
}

// MARK: - Month Name Helper

func monthDisplayName(_ month: Int) -> String {
    Calendar.current.monthSymbols[month - 1]
}

// MARK: - First-of-Month Date Helper

extension Calendar {
    func firstOfMonth(month: Int, year: Int) -> Date? {
        date(from: DateComponents(year: year, month: month, day: 1))
    }
}
