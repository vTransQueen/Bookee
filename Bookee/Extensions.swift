//
//  Extensions.swift
//  Bookee
//
//  General-purpose Swift, SwiftData, and SwiftUI extensions shared across the app.
//

import SwiftUI
import SwiftData

// MARK: - Set Toggle

extension Set {
    /// Removes the element if present, inserts it if absent.
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

// MARK: - ModelContext Logging

extension ModelContext {
    /// Saves the context and prints a labelled success or failure message.
    func saveWithLogging(_ label: String) {
        do {
            try save()
            print("💾 \(label)")
        } catch {
            print("❌ Error saving (\(label)): \(error)")
        }
    }
}

// MARK: - Color Hex

/// Extends Color with utilities for converting to/from hex strings for persistence in AppStorage.
/// Handles color space conversion and provides fallback values for edge cases.
extension Color {
    /// Initializes a Color from a hex string (e.g., "FF5733").
    /// The hex string should contain 6 characters representing RGB values.
    /// Uses precise conversion with proper rounding to maximum precision.
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let rInt = Int((rgbValue & 0xFF0000) >> 16)
        let gInt = Int((rgbValue & 0x00FF00) >> 8)
        let bInt = Int(rgbValue & 0x0000FF)

        let divisor = 255.0
        let r = (Double(rInt) / divisor * 1_000_000).rounded() / 1_000_000
        let g = (Double(gInt) / divisor * 1_000_000).rounded() / 1_000_000
        let b = (Double(bInt) / divisor * 1_000_000).rounded() / 1_000_000

        self.init(red: r, green: g, blue: b)
    }

    /// Converts a Color to a 6-character hex string (e.g., "FF5733") for storage.
    /// Performs color space conversion to sRGB and clamps values to valid ranges.
    /// Returns "007AFF" (default blue) if conversion fails.
    func toHex() -> String {
        let uiColor = UIColor(self)

        guard let rgbColor = uiColor.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent, options: nil
        ) else {
            print("⚠️ Failed to convert color to RGB space, using fallback")
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                let r = Int(max(0, min(255, (red   * 255.0).rounded())))
                let g = Int(max(0, min(255, (green * 255.0).rounded())))
                let b = Int(max(0, min(255, (blue  * 255.0).rounded())))
                return String(format: "%02X%02X%02X", r, g, b)
            }
            return "007AFF"
        }

        guard let components = rgbColor.components, components.count >= 3 else {
            print("⚠️ Color doesn't have RGB components")
            return "007AFF"
        }

        let r = Int(max(0, min(255, (components[0] * 255.0).rounded())))
        let g = Int(max(0, min(255, (components[1] * 255.0).rounded())))
        let b = Int(max(0, min(255, (components[2] * 255.0).rounded())))

        let hexString = String(format: "%02X%02X%02X", r, g, b)
        print("🎨 toHex() - RGB: (\(r), \(g), \(b)) -> \(hexString)")
        return hexString
    }
}
