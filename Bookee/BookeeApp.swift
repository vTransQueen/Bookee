//
//  K_TestApp.swift
//  K Test
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

@main
struct BookeeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    /// User-configurable appearance mode (light, dark, or system) persisted in UserDefaults
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    /// Hex color string for the app's tint/accent color, persisted in UserDefaults
    @AppStorage("highlightColorHex") private var highlightColorHex: String = "FF7EB5"
    
    /// Converts the stored hex string into a SwiftUI Color for use as the app tint
    private var highlightColor: Color {
        Color(hex: highlightColorHex)
    }
    
    init() {
        // Prepares navigation state restoration by checking UserDefaults and setting flags
        // Actual restoration happens in ContentView.onAppear when ModelContext is available
        restoreNavigationState()
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        
        // Create persistent storage at explicit location to ensure data survives across app updates
        let appGroupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appGroupURL.appendingPathComponent("K_Test.sqlite")
        
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
            
            // Attempt automatic recovery by deleting corrupted store files
            print("🔄 Attempting to recover by removing existing store...")
            
            let storeURL = modelConfiguration.url
            print("   Store location: \(storeURL.path)")
            
            // Delete all SwiftData-related files including SQLite and its support files
            let fileManager = FileManager.default
            let storeDirectory = storeURL.deletingLastPathComponent()
            
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
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
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
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .tint(highlightColor)
                .dynamicTypeSize(.large)
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
                
                // Create an automatic backup if enabled in settings
                createAutomaticBackup()
                
            case .active:
                // Permanently delete items that have been in trash for over 30 days
                cleanupOldDeletedItems()
            @unknown default:
                break
            }
        }
    }
    
    /// Permanently deletes items that have been soft-deleted for more than 30 days.
    /// Called when the app becomes active to keep the database clean.
    private func cleanupOldDeletedItems() {
        let context = sharedModelContainer.mainContext
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        // Query for all soft-deleted items (those with a deletedDate)
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { item in
                item.deletedDate != nil
            }
        )
        
        do {
            let deletedItems = try context.fetch(descriptor)
            
            // Find items deleted more than 30 days ago
            let itemsToDelete = deletedItems.filter { item in
                guard let deletedDate = item.deletedDate else { return false }
                return deletedDate < thirtyDaysAgo
            }
            
            // Permanently remove these items from the database
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
    
    /// Creates an automatic backup of all items when the app goes to background.
    /// Respects the user's "automaticBackupsEnabled" preference (defaults to enabled).
    private func createAutomaticBackup() {
        // Check if automatic backups are enabled in UserDefaults
        let automaticBackupsEnabled = UserDefaults.standard.bool(forKey: "automaticBackupsEnabled")
        
        // On first launch, the key won't exist, so default to enabled
        if UserDefaults.standard.object(forKey: "automaticBackupsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "automaticBackupsEnabled")
        }
        
        guard automaticBackupsEnabled else {
            print("⏭️ Skipping automatic backup - disabled by user")
            return
        }
        
        // Fetch all items (including deleted ones) for backup
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Item>()
        
        do {
            let items = try context.fetch(descriptor)
            BackupManager.shared.createBackup(items: items)
        } catch {
            print("❌ Failed to create automatic backup: \(error.localizedDescription)")
        }
    }
    
    /// Prepares navigation state restoration during app initialization.
    /// Reads saved state from UserDefaults and sets flags; actual restoration happens
    /// in ContentView.onAppear when the ModelContext becomes available.
    private func restoreNavigationState() {
        print("📂 Restoring navigation state at app initialization")
        
        // Decode the saved navigation state from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: NavigationStateManager.navigationStateKey),
              let state = try? JSONDecoder().decode(NavigationState.self, from: data) else {
            print("📂 No saved navigation state - showing fresh app")
            return
        }
        
        // Store the item timestamp for ContentView to resolve to an actual Item later
        if let itemTimestamp = state.currentItemTimestamp {
            print("📂 Will restore item with timestamp: \(itemTimestamp)")
            NavigationStateManager.shared.pendingItemTimestamp = itemTimestamp
        }
        
        // Store the year-month so ContentView can push month details after restoring the item
        if let yearMonth = state.currentYearMonth {
            print("📂 Will restore month details: \(yearMonth.month)/\(yearMonth.year)")
            NavigationStateManager.shared.pendingYearMonth = yearMonth
        }
        
        // Flag Settings view for restoration (ContentView will handle the actual navigation)
        if state.isViewingSettings {
            print("📂 Settings will be restored by ContentView")
            // Note: We don't append to navigation path here to avoid rendering glitches
        }
        
        print("📂 Navigation state restoration prepared")
    }
}
