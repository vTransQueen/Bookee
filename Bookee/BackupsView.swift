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
    @Query private var allBooks: [Book]
    @AppStorage("automaticBackupsEnabled") private var automaticBackupsEnabled: Bool = true
    @AppStorage("maxBackupsToKeep") private var maxBackupsToKeep: Int = 5
    @HighlightColorStorage private var highlightColor
    @AppStorage("showFooters") private var showFooters: Bool = true

    @State private var availableBackups: [Backup] = []
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackup: Backup?
    @State private var showingRestoreSuccess = false
    @State private var showingRestoreError = false
    @State private var showingCorruptionWarning = false
    @State private var restoreErrorMessage = ""
    @State private var corruptionWarningMessage = ""
    @State private var showingExportSheet = false
    @State private var backupToExport: Backup?
    @State private var exportDocument: BackupDocument?
    @State private var showingImportSheet = false
    @State private var newlyAddedBackupID: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var backupToDelete: Backup?

    var body: some View {
        Form {
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
            } header: {
                Text("Settings")
            } footer: {
                if showFooters {
                    if automaticBackupsEnabled {
                        Text("Backups are created automatically every time Bookee is closed. Tap \(Image(systemName: "plus.circle")) to manually create a backup.")
                    } else {
                        Text("Automatic backups are disabled. Tap \(Image(systemName: "plus.circle")) to manually create a backup.")
                    }
                }
            }

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
                                    .foregroundStyle(backup.id == newlyAddedBackupID ? highlightColor : .primary)
                                HStack(spacing: 4) {
                                    Text("\(backup.bookCount) book\(backup.bookCount == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("•").font(.caption).foregroundStyle(.secondary)
                                    Text(formatBackupSize(backup))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button { exportBackup(backup) } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            Button { selectedBackup = backup; showingRestoreConfirmation = true } label: {
                                Label("Restore", systemImage: "arrow.counterclockwise")
                            }
                            Divider()
                            Button(role: .destructive) { backupToDelete = backup; showingDeleteConfirmation = true } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { selectedBackup = backup; showingRestoreConfirmation = true } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }.tint(.blue)
                            Button { exportBackup(backup) } label: {
                                Image(systemName: "square.and.arrow.up")
                            }.tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { backupToDelete = backup; showingDeleteConfirmation = true } label: {
                                Image(systemName: "trash")
                            }.tint(.red)
                        }
                    }
                }
            } header: {
                Text("Backups")
            } footer: {
                if showFooters {
                    Text("Swipe right on a backup to restore or export it, or left to delete it.")
                }
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showingImportSheet = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }.tint(.primary)
                Spacer()
                Button { createManualBackup() } label: {
                    Label("Create Backup", systemImage: "plus")
                }.tint(.primary)
            }
        }
        .onAppear { loadBackups() }
        .onChange(of: maxBackupsToKeep) { oldValue, newValue in
            if newValue < oldValue {
                BackupManager.shared.cleanupOldBackups(keepingMax: newValue)
                loadBackups()
            }
        }
        .fileImporter(isPresented: $showingImportSheet, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importBackup(from: url)
            case .failure(let error):
                restoreErrorMessage = "Failed to import backup: \(error.localizedDescription)"
                showingRestoreError = true
            }
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: exportDocument,
            contentType: .json,
            defaultFilename: backupToExport.map { "Bookee_backup_\(makeTimestamp(from: $0.date)).json" }
        ) { result in
            if case .failure(let error) = result {
                print("❌ Failed to export backup: \(error)")
            }
            backupToExport = nil
            exportDocument = nil
        }
        .background {
            AlertContainer {
                Color.clear
                    .alert("Delete Backup?", isPresented: $showingDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { backupToDelete = nil }
                        Button("Delete", role: .destructive) {
                            if let b = backupToDelete { deleteBackup(b); backupToDelete = nil }
                        }
                    } message: {
                        Text("This will permanently delete the backup '\(backupToDelete?.displayName ?? "")'. This action cannot be undone.")
                    }
                    .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
                        Button("Cancel", role: .cancel) { selectedBackup = nil }
                        Button("Restore", role: .destructive) {
                            if let b = selectedBackup { restoreBackup(b) }
                        }
                    } message: {
                        Text("Restore \(selectedBackup?.bookCount ?? 0) book(s) from \(selectedBackup?.displayName ?? "")? This will replace all current data.")
                    }
                    .alert("Restore Successful", isPresented: $showingRestoreSuccess) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("Your data has been successfully restored from the backup.")
                    }
                    .alert("Error", isPresented: $showingRestoreError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(restoreErrorMessage)
                    }
                    .alert("Backup Corrupted", isPresented: $showingCorruptionWarning) {
                        Button("Cancel", role: .cancel) { selectedBackup = nil }
                        Button("Restore Anyway", role: .destructive) {
                            if let b = selectedBackup { performRestore(b) }
                        }
                    } message: {
                        Text(corruptionWarningMessage)
                    }
            }
        }
    }

    private func loadBackups() {
        availableBackups = BackupManager.shared.loadBackups()
    }

    private func formatBackupSize(_ backup: Backup) -> String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent("Backups/backup_\(backup.id.uuidString).json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return "Unknown size"
    }

    private func createManualBackup() {
        BackupManager.shared.createBackup(books: allBooks, force: true)
        loadBackups()
        if let newest = availableBackups.max(by: { $0.date < $1.date }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                withAnimation { newlyAddedBackupID = newest.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { newlyAddedBackupID = nil }
                }
            }
        }
    }

    private func deleteBackup(_ backup: Backup) {
        BackupManager.shared.deleteBackup(backup)
        loadBackups()
    }

    private func exportBackup(_ backup: Backup) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            exportDocument = BackupDocument(data: try encoder.encode(backup))
            backupToExport = backup
            showingExportSheet = true
        } catch {
            print("❌ Failed to encode backup for export: \(error)")
        }
    }

    private func importBackup(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            restoreErrorMessage = "Failed to access the selected file."
            showingRestoreError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(Backup.self, from: Data(contentsOf: url))
            selectedBackup = backup
            showingRestoreConfirmation = true
        } catch {
            restoreErrorMessage = "Failed to import backup: \(error.localizedDescription)"
            showingRestoreError = true
        }
    }

    private func restoreBackup(_ backup: Backup) {
        let (_, corrupted, details) = BackupManager.shared.validateBackup(backup)
        if corrupted > 0 {
            corruptionWarningMessage = "This backup contains \(corrupted) corrupted book(s). Corrupted data will be skipped:\n\n" + details.joined(separator: "\n")
            showingCorruptionWarning = true
        } else {
            performRestore(backup)
        }
    }

    private func performRestore(_ backup: Backup) {
        do {
            try BackupManager.shared.restoreBackup(backup, to: modelContext)
            selectedBackup = nil
            loadBackups()
            showingRestoreSuccess = true
        } catch {
            restoreErrorMessage = "Failed to restore backup: \(error.localizedDescription)"
            showingRestoreError = true
            loadBackups()
        }
    }
}

// MARK: - Backup Document

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
