//
//  BookeeApp.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

/// Gives App Intents and Home Screen quick actions access to the SwiftData container,
/// which isn't available via the SwiftUI environment outside of views.
enum SharedModelContainerHolder {
    static var container: ModelContainer?
}

@main
struct BookeeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    /// User-configurable appearance mode (light, dark, or system) persisted in UserDefaults
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    @HighlightColorStorage private var highlightColor

    @State private var navigationStateManager = NavigationStateManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        seedDefaultCategoriesIfNeeded()
        // NavigationStateManager.shared's own init (triggered above by this struct's
        // `navigationStateManager` property) already decoded the saved navigation state and
        // staged it (pendingRestorePath/pendingSubpageRestore) for ContentView to resolve into
        // real Items once ModelContext is available.
        SharedModelContainerHolder.container = sharedModelContainer
    }

    private func seedDefaultCategoriesIfNeeded() {
        let key = "transactionCategories"
        let ud = UserDefaults.standard
        let allDefaults = ["Gas", "Loan", "Cash", "Work", "Savings", "Recurring", "Restaurant", "Reimbursed", "Reimbursement", "Pending Reimbursement"]
        let protected = ["Reimbursed", "Reimbursement", "Pending Reimbursement"]

        let stored = ud.string(forKey: key)
        if stored == nil || stored == "[]" {
            ud.set(allDefaults.asAppStorageString, forKey: key)
        } else {
            // Ensure protected categories are always present for existing users
            var cats = (stored ?? "[]").asCategories
            var changed = false
            for cat in protected where !cats.contains(cat) {
                cats.append(cat)
                changed = true
            }
            if changed { ud.set(cats.asAppStorageString, forKey: key) }
        }
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        
        // Create persistent storage at explicit location to ensure data survives across app updates
        let appGroupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appGroupURL.appendingPathComponent("Bookee.sqlite")
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none  // CloudKit sync is disabled; change to .automatic or .private to enable
        )
        
        print("📂 Data store location: \(storeURL.path)")

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("✅ ModelContainer created successfully")

            // Confirm the SQLite file exists on disk
            if FileManager.default.fileExists(atPath: storeURL.path) {
                print("✅ Persistent store file confirmed at: \(storeURL.path)")
            }

            return container
        } catch let error as NSError {
            // Log detailed diagnostic information about the error
            print("❌ Error creating ModelContainer:")
            print("   Error domain: \(error.domain)")
            print("   Error code: \(error.code)")
            print("   Error description: \(error.localizedDescription)")
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("   Underlying error: \(underlyingError.localizedDescription)")
            }

            let fileManager = FileManager.default
            let storeURL = modelConfiguration.url
            let storeDirectory = storeURL.deletingLastPathComponent()

            // Step 1: a stale/mid-write -wal or -shm file (e.g. left behind after the app was force-killed
            // mid-save) is a common, fully recoverable cause of a failed open. Clear only those sidecar
            // files and retry before ever touching the actual data in the .sqlite file.
            print("🔄 Attempting to recover by clearing stale write-ahead-log files...")
            let sidecarSuffixes = ["-shm", "-wal"]
            for suffix in sidecarSuffixes {
                let sidecarURL = storeDirectory.appendingPathComponent(storeURL.lastPathComponent + suffix)
                if fileManager.fileExists(atPath: sidecarURL.path) {
                    try? fileManager.removeItem(at: sidecarURL)
                    print("   Removed sidecar: \(sidecarURL.lastPathComponent)")
                }
            }

            if let container = try? ModelContainer(for: schema, configurations: [modelConfiguration]) {
                print("✅ ModelContainer recovered after clearing stale write-ahead-log files — data preserved")
                return container
            }

            // Step 2: the store itself is unrecoverable. Wipe it, but restore from the most recent
            // automatic backup afterward rather than silently starting the user over with an empty app.
            print("❌ Store is unrecoverable — wiping and will attempt to restore from the latest automatic backup")
            print("   Store location: \(storeURL.path)")

            if let files = try? fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    // Remove SwiftData default files and SQLite database files
                    if file.lastPathComponent.hasPrefix("default") ||
                       file.pathExtension == "sqlite" ||
                       file.pathExtension == "sqlite-shm" ||
                       file.pathExtension == "sqlite-wal" {
                        do {
                            try fileManager.removeItem(at: file)
                            print("   ✅ Removed: \(file.lastPathComponent)")
                        } catch {
                            print("   ⚠️ Could not remove: \(file.lastPathComponent)")
                        }
                    }
                }
            }

            // Retry creating the container with fresh, empty storage
            do {
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ ModelContainer successfully recreated after cleanup")
                restoreFromLatestBackupIfAvailable(into: container)
                return container
            } catch {
                // Final fallback: use in-memory storage to prevent app crash (data won't persist)
                print("❌ Could not recreate ModelContainer with persistent storage")
                print("⚠️ Creating temporary in-memory container as fallback")

                let memoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )

                do {
                    let container = try ModelContainer(for: schema, configurations: [memoryConfig])
                    restoreFromLatestBackupIfAvailable(into: container)
                    return container
                } catch {
                    // Critical failure - even in-memory storage failed, indicates model definition issue
                    fatalError("""
                        Failed to create ModelContainer even with in-memory storage.
                        This indicates a fundamental issue with the data model.
                        Error: \(error.localizedDescription)

                        Please check:
                        1. Item.swift model definition is valid
                        2. All @Model properties are supported types
                        3. No circular dependencies in relationships
                        """)
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .preferredColorScheme(appearanceMode.colorScheme)
                    .tint(highlightColor)
                    .dynamicTypeSize(.large)

                if navigationStateManager.showingUniversalSearch {
                    UniversalSearchOverlay()
                        .tint(highlightColor)
                        .transition(.opacity)
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background, .inactive:
                // Persist SwiftData changes to disk when app moves to background or becomes inactive
                do {
                    try sharedModelContainer.mainContext.save()
                    print("💾 BookeeApp: Data saved to persistent storage")
                    print("✅ SwiftData context saved")
                } catch {
                    print("❌ Error saving context: \(error)")
                }
                
                // Save current navigation state (which view is open, which item is selected, etc.)
                NavigationStateManager.shared.saveNavigationState(modelContext: sharedModelContainer.mainContext)
                
                // Create an automatic backup if enabled in settings.
                createAutomaticBackup()
                
            case .active:
                // Permanently delete items that have been in trash for over 30 days
                cleanupOldDeletedItems()

                // Keep Home Screen quick actions registered
                UIApplication.shared.shortcutItems = AppDelegate.shortcutItems

                // Process any quick action that was stored by the AppDelegate.
                // Deferred one run loop so SwiftUI completes the foreground re-render first.
                if let kind = navigationStateManager.pendingQuickActionKind {
                    navigationStateManager.pendingQuickActionKind = nil
                    Task { @MainActor in
                        ShortcutRouter.openBudgetPicker(kind)
                    }
                }

                // Keep the Share Extension's budget list in sync.
                syncBudgetListToAppGroup()

                // Import any files/photos shared via the Share Extension.
                processPendingSharedAttachments()
            @unknown default:
                break
            }
        }
    }
    
    /// Permanently deletes items that have been soft-deleted for more than 30 days.
    /// Called when the app becomes active to keep the database clean.
    /// Runs on a background context so it never blocks the main thread during app foreground transitions.
    private func cleanupOldDeletedItems() {
        let container = sharedModelContainer
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let calendar = Calendar.current
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()

            let descriptor = FetchDescriptor<Item>(
                predicate: #Predicate { item in
                    item.deletedDate != nil
                }
            )

            do {
                let deletedItems = try context.fetch(descriptor)
                let itemsToDelete = deletedItems.filter { item in
                    guard let deletedDate = item.deletedDate else { return false }
                    return deletedDate < thirtyDaysAgo
                }
                for item in itemsToDelete {
                    context.delete(item)
                }
                if !itemsToDelete.isEmpty {
                    try context.save()
                    print("💾 BookeeApp: Cleaned up \(itemsToDelete.count) item(s) from trash")
                    print("✅ SwiftData context saved")
                }
            } catch {
                print("❌ Error cleaning up deleted items: \(error)")
            }
        }
    }
    
    /// Creates an automatic backup when the app goes to background.
    /// All work — fetching, diffing existing backups, and writing to disk — runs on a
    /// background thread via Task.detached so the main thread is never blocked during
    /// the app's background/foreground transition.
    private func createAutomaticBackup() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "automaticBackupsEnabled") == nil {
            ud.set(true, forKey: "automaticBackupsEnabled")
        }
        guard ud.bool(forKey: "automaticBackupsEnabled") else {
            print("⏭️ Skipping automatic backup - disabled by user")
            return
        }
        let container = sharedModelContainer
        Task.detached(priority: .background) {
            performAutomaticBackup(container: container)
        }
    }
    
    // MARK: - App Group sync (Share Extension)

    private let shareExtensionAppGroupID = "group.KaraCoding.Bookee"

    /// Writes the full active budget list (sorted by last opened) and the pinned timestamp
    /// to the shared App Group UserDefaults so the Share Extension can show a picker.
    private func syncBudgetListToAppGroup() {
        guard let sharedDefaults = UserDefaults(suiteName: shareExtensionAppGroupID) else { return }
        let context = sharedModelContainer.mainContext
        guard let allItems = try? context.fetch(FetchDescriptor<Item>()) else {
            sharedDefaults.removeObject(forKey: "budgetList")
            sharedDefaults.removeObject(forKey: "pinnedBudgetTimestamp")
            return
        }
        let budgets = allItems
            .filter { $0.deletedDate == nil && $0.itemType == .budget }
            .sorted { $0.lastOpenedDate > $1.lastOpenedDate }
        let list: [[String: Any]] = budgets.map {
            ["name": $0.name.isEmpty ? "Budget" : $0.name,
             "timestamp": $0.timestamp.timeIntervalSince1970]
        }
        sharedDefaults.set(list, forKey: "budgetList")
        let pinnedTs = UserDefaults.standard.double(forKey: SettingsKey.appContextMenuBudgetTimestamp)
        sharedDefaults.set(pinnedTs, forKey: "pinnedBudgetTimestamp")
    }

    /// Reads any files queued by the Share Extension, appends them as BudgetAttachments on
    /// the correct budget, and deletes the temporary files from the App Group container.
    private func processPendingSharedAttachments() {
        guard let sharedDefaults = UserDefaults(suiteName: shareExtensionAppGroupID),
              let pendingItems = sharedDefaults.array(forKey: "pendingSharedAttachments") as? [[String: Any]],
              !pendingItems.isEmpty else { return }

        // Clear the queue before any async work to prevent double-processing.
        sharedDefaults.removeObject(forKey: "pendingSharedAttachments")

        let container = sharedModelContainer
        let fallbackTs = UserDefaults.standard.double(forKey: SettingsKey.appContextMenuBudgetTimestamp)

        Task.detached {
            let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.KaraCoding.Bookee")
            let pendingDir = base?.appendingPathComponent("PendingAttachments")

            var loaded: [(data: Data, fileName: String, fileType: String, month: Int, year: Int, budgetTs: Double)] = []
            for item in pendingItems {
                guard let id       = item["id"]       as? String,
                      let fileName = item["fileName"] as? String,
                      let month    = item["month"]    as? Int,
                      let year     = item["year"]     as? Int,
                      let dir      = pendingDir else { continue }
                let budgetTs = (item["budgetTimestamp"] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? fallbackTs
                guard budgetTs > 0 else { continue }
                let fileURL = dir.appendingPathComponent(id)
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let fileType = item["fileType"] as? String ?? "other"
                loaded.append((data, fileName, fileType, month, year, budgetTs))
                try? FileManager.default.removeItem(at: fileURL)
            }

            guard !loaded.isEmpty else { return }

            let snapshot = loaded
            await MainActor.run {
                let context = container.mainContext
                guard let allItems = try? context.fetch(FetchDescriptor<Item>()) else { return }

                // Group by budget timestamp so each budget is fetched and saved once.
                let grouped = Dictionary(grouping: snapshot) { $0.budgetTs }
                for (budgetTs, items) in grouped {
                    guard let budget = allItems.first(where: {
                        $0.deletedDate == nil && $0.itemType == .budget &&
                        $0.timestamp.timeIntervalSince1970 == budgetTs
                    }) else { continue }
                    var (expenses, incomes, attachments, reallocations, odometerReadings) = budget.decodeBudgetData() ?? ([], [], [], [], [])
                    for item in items {
                        let type = sharedAttachmentType(fileType: item.fileType, fileName: item.fileName)
                        attachments.append(BudgetAttachment(
                            data: item.data, fileName: item.fileName,
                            fileType: type, month: item.month, year: item.year
                        ))
                    }
                    try? budget.encodeBudgetData(expenses: expenses, incomes: incomes, attachments: attachments, reallocations: reallocations, odometerReadings: odometerReadings)
                }
                try? context.save()
                print("✅ BookeeApp: Imported \(snapshot.count) shared attachment(s)")
                NotificationCenter.default.post(name: .sharedAttachmentsImported, object: nil)
            }
        }
    }
}

// MARK: -

/// Fetches all items using a background ModelContext and writes an automatic backup.
/// Called from Task.detached so all file I/O stays off the main thread.
private func performAutomaticBackup(container: ModelContainer) {
    let context = ModelContext(container)
    guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
    BackupManager.shared.createBackup(items: items)
}

/// Called only when the on-disk store had to be wiped because it failed to open. Restores the
/// most recent automatic backup into the freshly created (empty) container so a corrupted store
/// doesn't turn into total data loss for users who had automatic backups enabled.
private func restoreFromLatestBackupIfAvailable(into container: ModelContainer) {
    guard let latestBackup = BackupManager.shared.loadBackups().first else {
        print("⚠️ No automatic backup available to restore — starting with an empty store")
        return
    }
    let context = ModelContext(container)
    do {
        try BackupManager.shared.restoreBackup(latestBackup, to: context)
        print("✅ Restored data from automatic backup dated \(latestBackup.displayName)")
    } catch {
        print("❌ Failed to restore from backup after rebuilding the store: \(error)")
    }
}

/// Maps the fileType string stored by the Share Extension to the app's AttachmentType enum.
private func sharedAttachmentType(fileType: String, fileName: String) -> AttachmentType {
    switch fileType {
    case "image": return .image
    case "pdf":   return .pdf
    default:
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return .image
        case "pdf":                                         return .pdf
        case "doc", "docx", "txt", "rtf", "pages":         return .document
        default:                                            return .other
        }
    }
}
