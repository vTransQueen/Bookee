//
//  BackupsView.swift
//  Bookee
//
//  Created by Kara Eveland on 2/25/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @AppStorage("automaticBackupsEnabled") private var automaticBackupsEnabled: Bool = true
    @AppStorage("maxBackupsToKeep") private var maxBackupsToKeep: Int = 5
    @HighlightColorStorage private var highlightColor
    @State private var availableBackups: [Backup] = []
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackup: Backup?
    @State private var showingRestoreSuccess = false
    @State private var showingRestoreError = false
    @State private var showingCorruptionWarning = false
    @State private var restoreErrorMessage = ""
    @State private var corruptionWarningMessage = ""
    @State private var corruptedItemsCount = 0
    @State private var showingExportSheet = false
    @State private var backupToExport: Backup?
    @State private var exportDocument: BackupDocument?
    @State private var showingImportSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var backupToDelete: Backup?
    
    var body: some View {
        Form {
            // Backup settings section: retention limit and automatic backup toggle
            Section {
                Picker("Keep Backups", selection: $maxBackupsToKeep) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("15").tag(15)
                    Text("20").tag(20)
                }
                .pickerStyle(.menu)
                
                Toggle("Automatic Backups", isOn: $automaticBackupsEnabled)
            }
            
            // Backups list section: displays all available backups with context menu actions
            Section {
                if availableBackups.isEmpty {
                    Text("No backups available")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(availableBackups) { backup in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.displayName)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    Text("\(backup.itemCount) item\(backup.itemCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatBackupSize(backup))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                exportBackup(backup)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.primary)
                            Button {
                                selectedBackup = backup
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingRestoreConfirmation = true }
                            } label: {
                                Label("Restore", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.primary)
                            Divider()
                            Button(role: .destructive) {
                                backupToDelete = backup
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingDeleteConfirmation = true }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                selectedBackup = backup
                                showingRestoreConfirmation = true
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .tint(.blue)
                            Button {
                                exportBackup(backup)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                backupToDelete = backup
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            PageNavigationToolbarItem(label: "Backups", systemImage: "externaldrive", titleOnly: true)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { NavigationStateManager.shared.showingUniversalSearch = true } } label: {
                    Image(systemName: "magnifyingglass")
                }
                .tint(.primary)
            }
            // Bottom toolbar with import and create backup buttons
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .tint(.primary)
                
                Spacer()
                
                Button {
                    createManualBackup()
                } label: {
                    Label("Create Backup", systemImage: "plus")
                }
                .tint(.primary)
            }
        }
        .onAppear {
            loadBackups()
        }
        .onChange(of: maxBackupsToKeep) { oldValue, newValue in
            // When user reduces the backup retention limit, immediately delete excess backups
            if newValue < oldValue {
                BackupManager.shared.cleanupOldBackups(keepingMax: newValue)
                loadBackups()
            }
        }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                importBackup(from: url)
            case .failure(let error):
                print("❌ Failed to import backup: \(error)")
                restoreErrorMessage = "Failed to import backup: \(error.localizedDescription)"
                showingRestoreError = true
            }
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: exportDocument,
            contentType: .json,
            defaultFilename: backupToExport.map { backup in
                "Bookee_backup_\(makeTimestamp(from: backup.date)).json"
            }
        ) { result in
            switch result {
            case .success(let url):
                print("✅ Backup exported to: \(url)")
            case .failure(let error):
                print("❌ Failed to export backup: \(error)")
            }
            // Clean up export state
            backupToExport = nil
            exportDocument = nil
        }
        .background {
            // Invisible AlertContainer wraps all alerts to apply primary tint instead of custom highlight color
            AlertContainer {
                Color.clear
                    // Delete backup confirmation alert
                    .alert("Delete Backup?", isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) {
                            backupToDelete = nil
                        }
                        Button("Delete", role: .destructive) {
                            if let backup = backupToDelete {
                                deleteBackup(backup)
                                backupToDelete = nil
                            }
                        }
                    } message: {
                        if let backup = backupToDelete {
                            Text("This will permanently delete the backup '\(backup.displayName)'. This action cannot be undone.")
                        } else {
                            Text("This will permanently delete the backup. This action cannot be undone.")
                        }
                    }
                    // Restore backup confirmation alert
                    .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
                        Button("Cancel", role: .cancel) {
                            selectedBackup = nil
                        }
                        Button("Restore", role: .destructive) {
                            if let backup = selectedBackup {
                                restoreBackup(backup)
                            }
                        }
                    } message: {
                        if let backup = selectedBackup {
                            Text("Restore \(backup.itemCount) item(s) from \(backup.displayName)? This will replace all current data.")
                        } else {
                            Text("This will replace all current data.")
                        }
                    }
                    // Restore success confirmation alert
                    .alert("Restore Successful", isPresented: $showingRestoreSuccess) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("Your data has been successfully restored from the backup.")
                    }
                    // Restore error alert
                    .alert("Error", isPresented: $showingRestoreError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(restoreErrorMessage)
                    }
                    // Backup corruption warning alert with option to restore anyway
                    .alert("Backup Corrupted", isPresented: $showingCorruptionWarning) {
                        Button("Cancel", role: .cancel) {
                            selectedBackup = nil
                        }
                        Button("Restore Anyway", role: .destructive) {
                            if let backup = selectedBackup {
                                // Restore backup, skipping validation (corrupted data will be cleared)
                                performRestore(backup)
                            }
                        }
                    } message: {
                        Text(corruptionWarningMessage)
                    }
            }
        }
    }
    
    // MARK: - Backup Management Methods
    
    /// Loads all available backups from BackupManager and updates the UI
    private func loadBackups() {
        availableBackups = BackupManager.shared.loadBackups()
    }
    
    /// Calculates and formats the file size of a backup in human-readable format (e.g., "2.3 KB")
    /// - Parameter backup: The backup to check
    /// - Returns: Formatted size string, or "Unknown size" if unable to determine
    private func formatBackupSize(_ backup: Backup) -> String {
        // Build the backup file path
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDirectory = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        let filename = "backup_\(backup.id.uuidString).json"
        let fileURL = backupDirectory.appendingPathComponent(filename)
        
        // Get file size from disk
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            print("⚠️ Failed to get file size for backup: \(error)")
        }
        
        return "Unknown size"
    }
    
    private func createManualBackup() {
        BackupManager.shared.createBackup(items: allItems, force: true)
        loadBackups()
    }
    
    /// Deletes a backup from disk and refreshes the backups list
    /// - Parameter backup: The backup to delete
    private func deleteBackup(_ backup: Backup) {
        BackupManager.shared.deleteBackup(backup)
        loadBackups()
    }
    
    /// Encodes a backup as JSON and prepares it for export via the file exporter
    /// - Parameter backup: The backup to export
    private func exportBackup(_ backup: Backup) {
        // Encode backup to JSON with pretty printing
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            
            // Prepare the file export document
            exportDocument = BackupDocument(data: data)
            backupToExport = backup
            showingExportSheet = true
        } catch {
            print("❌ Failed to encode backup for export: \(error)")
        }
    }
    
    /// Imports a backup from a JSON file, decodes it, and prompts the user to restore it
    /// - Parameter url: Security-scoped URL of the backup file to import
    private func importBackup(from url: URL) {
        // Request access to the security-scoped resource (required for files from file picker)
        guard url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to access security-scoped resource")
            restoreErrorMessage = "Failed to access the selected file."
            showingRestoreError = true
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        do {
            // Read and decode the backup file
            let data = try Data(contentsOf: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(Backup.self, from: data)
            
            print("✅ Successfully imported backup: \(backup.displayName)")
            
            // Prompt user to restore the imported backup
            selectedBackup = backup
            showingRestoreConfirmation = true
            
        } catch {
            print("❌ Failed to import backup: \(error)")
            restoreErrorMessage = "Failed to import backup: \(error.localizedDescription)"
            showingRestoreError = true
        }
    }
    
    /// Validates a backup for corruption before restoring. If corrupted items are found, warns the user.
    /// Otherwise, proceeds directly to restore.
    /// - Parameter backup: The backup to validate and restore
    private func restoreBackup(_ backup: Backup) {
        // Validate the backup's JSON data integrity
        print("🔍 Validating backup before restore: \(backup.displayName)")
        
        let (validItems, corruptedItems, corruptedDetails) = BackupManager.shared.validateBackup(backup)
        
        print("✅ Validation complete: \(validItems) valid, \(corruptedItems) corrupted")
        
        if corruptedItems > 0 {
            // Backup contains corrupted data - warn user and offer option to continue
            print("⚠️ Backup contains corrupted data:")
            for detail in corruptedDetails {
                print("  - \(detail)")
            }
            
            corruptedItemsCount = corruptedItems
            corruptionWarningMessage = "This backup contains \(corruptedItems) corrupted item(s). Corrupted data will be skipped during restoration:\n\n" + corruptedDetails.joined(separator: "\n")
            showingCorruptionWarning = true
        } else {
            // Backup is clean - proceed with restore
            performRestore(backup)
        }
    }
    
    /// Performs the actual backup restoration by delegating to BackupManager
    /// Shows success or error alerts based on the outcome
    /// - Parameter backup: The backup to restore
    private func performRestore(_ backup: Backup) {
        do {
            try BackupManager.shared.restoreBackup(backup, to: modelContext)
            selectedBackup = nil
            
            // Reload the backups list in case restoration created/modified backups
            loadBackups()
            
            // Show success alert
            showingRestoreSuccess = true
            
            print("✅ BackupsView: Restore completed successfully")
        } catch {
            print("❌ BackupsView: Restore failed with error: \(error)")
            restoreErrorMessage = "Failed to restore backup: \(error.localizedDescription)"
            showingRestoreError = true
            
            // Reload backups even on failure to reflect current state
            loadBackups()
        }
    }
}

// MARK: - Backup Document

/// FileDocument wrapper for exporting backup data as a JSON file
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var data: Data
    
    /// Creates a document from backup data for export
    init(data: Data) {
        self.data = data
    }
    
    /// Creates a document from an imported file (required by FileDocument protocol)
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    /// Wraps the backup data for writing to disk (required by FileDocument protocol)
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

