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
        } catch {
            // Do NOT delete the database — silently wiping it would destroy user data.
            // Fall back to in-memory so the app stays open; the on-disk file is preserved
            // and can be recovered manually or via the in-app Backups screen.
            print("❌ Error creating ModelContainer: \(error.localizedDescription)")
            print("⚠️ Your data file is preserved at: \(storeURL.path)")
            print("⚠️ Running in-memory only — changes will not be saved until relaunch resolves the error.")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            LibraryView()
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
