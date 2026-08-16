//
//  BookeeApp.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import SwiftData

@main
struct BookeeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("highlightColorHex") private var highlightColorHex: String = "FF7EB5"

    private var highlightColor: Color {
        Color(hex: highlightColorHex)
    }

    init() {
        restoreNavigationState()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
        ])

        let appGroupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appGroupURL.appendingPathComponent("Bookee.sqlite")

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        print("📂 Data store location: \(storeURL.path)")

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("✅ ModelContainer created successfully")
            return container
        } catch let error as NSError {
            print("❌ Error creating ModelContainer: \(error.localizedDescription)")
            print("🔄 Attempting to recover by removing existing store...")

            let fileManager = FileManager.default
            let storeDirectory = modelConfiguration.url.deletingLastPathComponent()

            if let files = try? fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    if file.lastPathComponent.hasPrefix("default") ||
                       file.pathExtension == "sqlite" ||
                       file.pathExtension == "sqlite-shm" ||
                       file.pathExtension == "sqlite-wal" {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }

            do {
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ ModelContainer successfully recreated after cleanup")
                return container
            } catch {
                print("⚠️ Creating temporary in-memory container as fallback")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .tint(highlightColor)
                .dynamicTypeSize(.xLarge)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                do {
                    try sharedModelContainer.mainContext.save()
                } catch {
                    print("❌ Error saving context: \(error)")
                }
                NavigationStateManager.shared.saveNavigationState(modelContext: sharedModelContainer.mainContext)
                createAutomaticBackup()
            case .active:
                cleanupOldDeletedBooks()
            @unknown default:
                break
            }
        }
    }

    private func cleanupOldDeletedBooks() {
        let context = sharedModelContainer.mainContext
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.deletedDate != nil })
        do {
            let deleted = try context.fetch(descriptor)
            let toDelete = deleted.filter { ($0.deletedDate ?? Date()) < thirtyDaysAgo }
            for book in toDelete { context.delete(book) }
            if !toDelete.isEmpty { try context.save() }
        } catch {
            print("❌ Error cleaning up deleted books: \(error)")
        }
    }

    private func createAutomaticBackup() {
        if UserDefaults.standard.object(forKey: "automaticBackupsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "automaticBackupsEnabled")
        }
        guard UserDefaults.standard.bool(forKey: "automaticBackupsEnabled") else { return }

        let descriptor = FetchDescriptor<Book>()
        do {
            let books = try sharedModelContainer.mainContext.fetch(descriptor)
            BackupManager.shared.createBackup(books: books)
        } catch {
            print("❌ Failed to create automatic backup: \(error.localizedDescription)")
        }
    }

    private func restoreNavigationState() {}
}
