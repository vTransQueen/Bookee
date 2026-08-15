//
//  BackupManager.swift
//  K Test
//
//  Created by Kara Eveland on 2/25/26.
//

import Foundation
import SwiftData

// MARK: - Backup Data Structures

/// Represents a single budget item in the backup with all its associated data
struct BackupItem: Codable, Equatable {
    let timestamp: Date
    let lastOpenedDate: Date
    let lastModifiedDate: Date
    let name: String
    let budgetAmount: Double?  // Deprecated - no longer used, kept for backward compatibility
    let manualSortOrder: Int
    let taxSavingsPercentage: Double
    let isTaxSavingsEnabled: Bool
    let itemType: String
    let targetYear: Int?
    let deletedDate: Date?
    let expensesData: Data?  // JSON-encoded expenses array
    let incomesData: Data?  // JSON-encoded incomes array
    let attachmentsData: Data?  // JSON-encoded budget attachments (photos and files)
    let reallocationsData: Data?  // JSON-encoded fund reallocation entries
    let taxesData: Data?  // Deprecated - kept for backward compatibility only
    let isAutoIncomeDisabled: Bool?  // Deprecated - kept for backward compatibility only
    let disabledAutoIncomeAmount: Double?  // Deprecated - kept for backward compatibility only
    let disabledAutoIncomeFrequency: String?  // Deprecated - kept for backward compatibility only
    let disabledAutoIncomeDate: Date?  // Deprecated - kept for backward compatibility only
    let lastTaxSavingsPercentage: Double?
    let hideExpensesRow: Bool?
    let hideTaxesGoalRow: Bool?
    let hideReallocationsRow: Bool?
    let hideIncomeSurplusRow: Bool?
    let hideOtherIncomeRow: Bool?
    let hiddenFilterCategories: String?

    /// Custom equality check that ignores lastOpenedDate to prevent unnecessary backups
    /// when only the "last opened" timestamp changes without actual data modifications
    static func == (lhs: BackupItem, rhs: BackupItem) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
               lhs.lastModifiedDate == rhs.lastModifiedDate &&
               lhs.name == rhs.name &&
               lhs.manualSortOrder == rhs.manualSortOrder &&
               lhs.taxSavingsPercentage == rhs.taxSavingsPercentage &&
               lhs.isTaxSavingsEnabled == rhs.isTaxSavingsEnabled &&
               lhs.itemType == rhs.itemType &&
               lhs.targetYear == rhs.targetYear &&
               lhs.deletedDate == rhs.deletedDate &&
               lhs.expensesData == rhs.expensesData &&
               lhs.incomesData == rhs.incomesData &&
               lhs.attachmentsData == rhs.attachmentsData &&
               lhs.reallocationsData == rhs.reallocationsData &&
               lhs.lastTaxSavingsPercentage == rhs.lastTaxSavingsPercentage &&
               lhs.hideExpensesRow == rhs.hideExpensesRow &&
               lhs.hideTaxesGoalRow == rhs.hideTaxesGoalRow &&
               lhs.hideReallocationsRow == rhs.hideReallocationsRow &&
               lhs.hideIncomeSurplusRow == rhs.hideIncomeSurplusRow &&
               lhs.hideOtherIncomeRow == rhs.hideOtherIncomeRow &&
               lhs.hiddenFilterCategories == rhs.hiddenFilterCategories
               // Note: Deprecated properties omitted from comparison
    }
}

/// App-level settings snapshot included in each backup
struct BackupAppSettings: Codable {
    let selectedCurrency: String?
    let appearanceMode: String?
    let dateFormat: String?
    let sortOrder: String?
    let userName: String?
    let highlightColorHex: String?
    let transactionCategories: String?  // JSON-encoded [String] of user-created category names
    let automaticBackupsEnabled: Bool?
    let maxBackupsToKeep: Int?
    let showFooters: Bool?
}

/// Represents a complete backup snapshot with metadata
struct Backup: Codable, Identifiable {
    let id: UUID
    let date: Date
    let itemCount: Int
    let items: [BackupItem]
    let appSettings: BackupAppSettings?  // Optional for backward compatibility with older backups

    /// User-friendly display name showing date and time of backup
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Backup Manager

/// Manages automatic and manual backups of app data to the local file system
class BackupManager {
    static let shared = BackupManager()
    
    private let backupDirectory: URL
    
    private init() {
        // Create backups directory in app's documents folder
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        backupDirectory = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        
        // Ensure backup directory exists
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        
        print("📂 Backup directory: \(backupDirectory.path)")
    }
    
    /// Retrieves the maximum number of backups to keep from UserDefaults (defaults to 5)
    private var maxBackups: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxBackupsToKeep")
        return stored != 0 ? stored : 5
    }
    
    // MARK: - Create Backup
    
    /// Creates a new backup from the current data, skipping if no changes detected
    /// - Parameters:
    ///   - items: The budget items to back up
    ///   - force: If true, creates backup even if data hasn't changed (useful for manual backups)
    func createBackup(items: [Item], force: Bool = false) {
        do {
            // Convert SwiftData items to BackupItem format
            let backupItems = items.map { item in
                BackupItem(
                    timestamp: item.timestamp,
                    lastOpenedDate: item.lastOpenedDate,
                    lastModifiedDate: item.lastModifiedDate,
                    name: item.name,
                    budgetAmount: nil,  // Deprecated - kept as nil for backward compatibility
                    manualSortOrder: item.manualSortOrder,
                    taxSavingsPercentage: item.taxSavingsPercentage,
                    isTaxSavingsEnabled: item.isTaxSavingsEnabled,
                    itemType: item.itemType.rawValue,
                    targetYear: item.targetYear,
                    deletedDate: item.deletedDate,
                    expensesData: item.expensesData,
                    incomesData: item.incomesData,
                    attachmentsData: item.attachmentsData,
                    reallocationsData: item.reallocationsData,
                    taxesData: nil,  // Deprecated - kept for backward compatibility only
                    isAutoIncomeDisabled: nil,  // Deprecated - no longer used
                    disabledAutoIncomeAmount: nil,  // Deprecated - no longer used
                    disabledAutoIncomeFrequency: nil,  // Deprecated - no longer used
                    disabledAutoIncomeDate: nil,  // Deprecated - no longer used
                    lastTaxSavingsPercentage: item.lastTaxSavingsPercentage,
                    hideExpensesRow: item.hideExpensesRow,
                    hideTaxesGoalRow: item.hideTaxesGoalRow,
                    hideReallocationsRow: item.hideReallocationsRow,
                    hideIncomeSurplusRow: item.hideIncomeSurplusRow,
                    hideOtherIncomeRow: item.hideOtherIncomeRow,
                    hiddenFilterCategories: item.hiddenFilterCategories
                )
            }
            
            // Skip backup creation if no data has changed (unless forced by user)
            if !force && !hasDataChanged(newBackupItems: backupItems) {
                print("⏭️ Skipping backup - no data changes detected")
                return
            }
            
            // Snapshot app-level settings from UserDefaults
            let ud = UserDefaults.standard
            let settings = BackupAppSettings(
                selectedCurrency: ud.string(forKey: "selectedCurrency"),
                appearanceMode: ud.string(forKey: "appearanceMode"),
                dateFormat: ud.string(forKey: "dateFormat"),
                sortOrder: ud.string(forKey: "sortOrder"),
                userName: ud.string(forKey: "userName"),
                highlightColorHex: ud.string(forKey: "highlightColorHex"),
                transactionCategories: ud.string(forKey: "transactionCategories"),
                automaticBackupsEnabled: ud.object(forKey: "automaticBackupsEnabled") != nil ? ud.bool(forKey: "automaticBackupsEnabled") : nil,
                maxBackupsToKeep: ud.object(forKey: "maxBackupsToKeep") != nil ? ud.integer(forKey: "maxBackupsToKeep") : nil,
                showFooters: ud.object(forKey: "showFooters") != nil ? ud.bool(forKey: "showFooters") : nil
            )

            // Create backup object with metadata
            let backup = Backup(
                id: UUID(),
                date: Date(),
                itemCount: items.count,
                items: backupItems,
                appSettings: settings
            )
            
            // Encode and save backup to JSON file
            let filename = "backup_\(backup.id.uuidString).json"
            let fileURL = backupDirectory.appendingPathComponent(filename)
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            try data.write(to: fileURL)
            
            print("✅ Backup created: \(backup.displayName) with \(items.count) items")
            
            // Remove old backups beyond the retention limit
            cleanupOldBackups()
            
        } catch {
            print("❌ Failed to create backup: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load Backups
    
    /// Loads all available backups from disk, sorted by date (newest first)
    /// - Returns: Array of Backup objects, or empty array if none found or on error
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
            
            // Sort by date, newest first
            backups.sort { $0.date > $1.date }
            
            print("📂 Loaded \(backups.count) backup(s)")
            return backups
            
        } catch {
            print("❌ Failed to load backups: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Restore Backup
    
    /// Restores data from a backup by deleting all existing items and recreating them
    /// - Parameters:
    ///   - backup: The backup to restore from
    ///   - modelContext: The SwiftData model context to perform operations in
    /// - Throws: Errors from SwiftData operations or JSON validation failures
    func restoreBackup(_ backup: Backup, to modelContext: ModelContext) throws {
        print("🔄 Starting backup restoration...")
        
        // Fetch and delete all existing items from SwiftData
        let fetchDescriptor = FetchDescriptor<Item>()
        let existingItems = try modelContext.fetch(fetchDescriptor)
        
        print("🗑️ Deleting \(existingItems.count) existing item(s)")
        for item in existingItems {
            modelContext.delete(item)
        }
        
        // Persist deletions before inserting new data
        try modelContext.save()
        print("💾 BackupManager: Deleted \(existingItems.count) existing item(s)")
        print("✅ SwiftData context saved")
        
        // Recreate items from backup data
        var restoredCount = 0
        
        for backupItem in backup.items {
            let n = backupItem.name
            let validatedExpensesData     = validateOrClear(backupItem.expensesData,     as: [Expense].self,          label: "expenses",     itemName: n)
            let validatedIncomesData      = validateOrClear(backupItem.incomesData,      as: [Income].self,           label: "incomes",      itemName: n)
            let validatedAttachmentsData  = validateOrClear(backupItem.attachmentsData,  as: [BudgetAttachment].self, label: "attachments",  itemName: n)
            let validatedReallocationsData = validateOrClear(backupItem.reallocationsData, as: [Reallocation].self,   label: "reallocations", itemName: n)
            // Note: taxesData is deprecated and no longer validated or restored
            
            // Create new SwiftData item from validated backup data
            let item = Item(
                timestamp: backupItem.timestamp,
                name: backupItem.name,
                manualSortOrder: backupItem.manualSortOrder,
                taxSavingsPercentage: backupItem.taxSavingsPercentage,
                isTaxSavingsEnabled: backupItem.isTaxSavingsEnabled,
                itemType: ItemType(rawValue: backupItem.itemType) ?? .budget,
                targetYear: backupItem.targetYear
            )
            
            // Restore metadata properties
            item.lastOpenedDate = backupItem.lastOpenedDate
            item.lastModifiedDate = backupItem.lastModifiedDate
            item.deletedDate = backupItem.deletedDate
            
            // Restore only validated data to prevent corruption
            item.expensesData = validatedExpensesData
            item.incomesData = validatedIncomesData
            item.attachmentsData = validatedAttachmentsData
            item.reallocationsData = validatedReallocationsData
            item.lastTaxSavingsPercentage = backupItem.lastTaxSavingsPercentage
            item.hideExpensesRow = backupItem.hideExpensesRow
            item.hideTaxesGoalRow = backupItem.hideTaxesGoalRow
            item.hideReallocationsRow = backupItem.hideReallocationsRow
            item.hideIncomeSurplusRow = backupItem.hideIncomeSurplusRow
            item.hideOtherIncomeRow = backupItem.hideOtherIncomeRow
            item.hiddenFilterCategories = backupItem.hiddenFilterCategories
            // Note: Deprecated fields (taxesData, budgetAmount, auto income state) are not restored
            
            modelContext.insert(item)
            restoredCount += 1
            print("✅ Restored item '\(backupItem.name)'")
        }
        
        // Persist all restored items to SwiftData
        try modelContext.save()
        print("💾 BackupManager: Restored \(restoredCount) item(s) from backup")
        print("✅ SwiftData context saved")

        // Restore app-level settings if present in this backup
        if let settings = backup.appSettings {
            let ud = UserDefaults.standard
            if let v = settings.selectedCurrency      { ud.set(v, forKey: "selectedCurrency") }
            if let v = settings.appearanceMode        { ud.set(v, forKey: "appearanceMode") }
            if let v = settings.dateFormat            { ud.set(v, forKey: "dateFormat") }
            if let v = settings.sortOrder             { ud.set(v, forKey: "sortOrder") }
            if let v = settings.userName              { ud.set(v, forKey: "userName") }
            if let v = settings.highlightColorHex     { ud.set(v, forKey: "highlightColorHex") }
            if let v = settings.transactionCategories    { ud.set(v, forKey: "transactionCategories") }
            if let v = settings.automaticBackupsEnabled  { ud.set(v, forKey: "automaticBackupsEnabled") }
            if let v = settings.maxBackupsToKeep         { ud.set(v, forKey: "maxBackupsToKeep") }
            if let v = settings.showFooters              { ud.set(v, forKey: "showFooters") }
            print("✅ App settings restored from backup")
        }

        print("✅ Backup restoration complete: \(restoredCount) items restored")
        print("✅ Final item count: \(try modelContext.fetch(fetchDescriptor).count)")
    }
    
    // MARK: - Delete Backup
    
    /// Deletes a specific backup file from disk
    /// - Parameter backup: The backup to delete
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

    /// Validates optional JSON data and logs success/failure. Returns the data if valid, nil otherwise.
    private func validateOrClear<T: Decodable>(_ data: Data?, as type: T.Type, label: String, itemName: String) -> Data? {
        guard let data else { return nil }
        if validateJSONData(data, as: type) {
            print("✅ Validated \(label) data for '\(itemName)'")
            return data
        } else {
            print("⚠️ Corrupted \(label) data for '\(itemName)' - will be cleared")
            return nil
        }
    }

    /// Attempts to decode JSON data to verify it's not corrupted
    private func validateJSONData<T: Decodable>(_ data: Data, as type: T.Type) -> Bool {
        do {
            _ = try JSONDecoder().decode(type, from: data)
            return true
        } catch {
            return false
        }
    }
    
    /// Validates all items in a backup to check for JSON corruption
    /// - Parameter backup: The backup to validate
    /// - Returns: Tuple containing (valid item count, corrupted item count, array of corruption details)
    func validateBackup(_ backup: Backup) -> (valid: Int, corrupted: Int, details: [String]) {
        var validItems = 0, corruptedItems = 0
        var corruptedDetails: [String] = []
        for item in backup.items {
            var issues: [String] = []
            func check<T: Decodable>(_ data: Data?, as type: T.Type, label: String) {
                if let d = data, !validateJSONData(d, as: type) { issues.append("corrupted \(label)") }
            }
            check(item.expensesData,     as: [Expense].self,          label: "expenses")
            check(item.incomesData,      as: [Income].self,           label: "incomes")
            check(item.attachmentsData,  as: [BudgetAttachment].self, label: "attachments")
            check(item.reallocationsData, as: [Reallocation].self,    label: "reallocations")
            if issues.isEmpty {
                validItems += 1
            } else {
                corruptedItems += 1
                let name = item.name.isEmpty ? "Untitled" : item.name
                corruptedDetails.append("\(name): \(issues.joined(separator: ", "))")
            }
        }
        return (validItems, corruptedItems, corruptedDetails)
    }
    
    // MARK: - Cleanup
    
    /// Compares new backup data with the most recent backup to determine if data has changed
    /// - Parameter newBackupItems: The new backup items to compare
    /// - Returns: True if data has changed or no prior backup exists, false if identical
    private func hasDataChanged(newBackupItems: [BackupItem]) -> Bool {
        let existingBackups = loadBackups()
        
        // If no backups exist, data has "changed" (first backup)
        guard let mostRecentBackup = existingBackups.first else {
            return true
        }
        
        // Quick count comparison before detailed comparison
        if newBackupItems.count != mostRecentBackup.items.count {
            return true
        }
        
        // Sort both arrays by timestamp for consistent item-by-item comparison
        let sortedNewItems = newBackupItems.sorted { $0.timestamp < $1.timestamp }
        let sortedOldItems = mostRecentBackup.items.sorted { $0.timestamp < $1.timestamp }
        
        // Perform deep comparison using custom equality operator
        for (newItem, oldItem) in zip(sortedNewItems, sortedOldItems) {
            if newItem != oldItem {
                return true
            }
        }
        
        // Items are identical to the most recent backup
        return false
    }
    
    /// Removes oldest backups when exceeding the retention limit
    /// - Parameter keepingMax: Optional override for maximum backups to keep; if nil, uses user's setting
    func cleanupOldBackups(keepingMax: Int? = nil) {
        let backups = loadBackups()
        let limit = keepingMax ?? maxBackups
        
        // Delete backups beyond the retention limit (oldest first)
        if backups.count > limit {
            let backupsToDelete = backups.suffix(from: limit)
            
            for backup in backupsToDelete {
                deleteBackup(backup)
            }
            
            print("🧹 Cleaned up \(backupsToDelete.count) old backup(s), keeping \(limit)")
        }
    }
    
}
