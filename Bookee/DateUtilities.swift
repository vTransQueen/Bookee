//
//  DateUtilities.swift
//  Bookee
//
//  Created by Kara Eveland on 5/6/26.
//

import Foundation

// MARK: - Date Utilities

extension Date {
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
