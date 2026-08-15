//
//  AttachmentViews.swift
//  K Test
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Overview
// This file provides attachment management for income, budget, and expense entries.
//
// Architecture:
// - AttachmentManagementView: Displays income/expense attachments with view/delete actions
// - BudgetAttachmentManagementView: Displays budget attachments with optional selection mode and customizable highlight color
//- BudgetAttachmentHelper: Static helper methods for loading photos and documents into budget attachments
// - AttachmentRowView: Individual attachment row with tap-to-view and context menu delete
// - BudgetAttachmentRowView: Budget attachment row with optional selection mode
// - AttachmentViewerSheet: Full-screen viewer for attachments with sharing
// - BudgetAttachmentViewerSheet: Full-screen viewer for budget attachments with editable filename and sharing
// - PDFViewerRepresentable: UIViewRepresentable wrapper for PDFView to display PDF attachments
// - ShareSheet: UIViewControllerRepresentable wrapper for UIActivityViewController
// - PhotoPickerRepresentable: UIViewControllerRepresentable wrapper for PHPickerViewController (privacy-friendly)
//
// Privacy:
// Uses PHPickerViewController which doesn't require photo library access permissions.
// Users can select photos without granting full library access to the app.
//
// Usage:
// 1. Add AttachmentManagementView or BudgetAttachmentManagementView to the form
// 2. Use BudgetAttachmentHelper for loading photos/documents with month/year context

// MARK: - Shared Attachment Share Helper

/// Writes attachment data to a temporary file and returns the URL for sharing.
/// Shared by AttachmentViewerSheet and BudgetAttachmentViewerSheet.
private func prepareShareURL(fileName: String, data: Data) -> URL? {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    do {
        try data.write(to: tempURL)
        return tempURL
    } catch {
        print("❌ Error creating temporary file for sharing: \(error)")
        return nil
    }
}

// MARK: - Shared Attachment Delete Alert Modifier

extension View {
    /// Attaches a "Delete Attachment?" confirmation alert as a background overlay.
    /// Shared by AttachmentManagementView and BudgetAttachmentManagementView to avoid
    /// duplicating the identical alert block.
    func attachmentDeleteAlert(
        isPresented: Binding<Bool>,
        fileName: String?,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.background {
            AlertContainer {
                Color.clear
                    .alert("Delete Attachment?", isPresented: isPresented) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                    } message: {
                        if let fileName = fileName {
                            Text("This will permanently delete '\(fileName)'. This action cannot be undone.")
                        }
                    }
            }
        }
    }
}

// MARK: - Budget Attachment Pickers

extension View {
    /// Attaches a photo-picker sheet and file-importer for budget attachments,
    /// tagging new attachments with the given month and year.
    func budgetAttachmentPickers(
        showingPhotoPicker: Binding<Bool>,
        showingFilePicker: Binding<Bool>,
        attachments: Binding<[BudgetAttachment]>,
        month: Int,
        year: Int
    ) -> some View {
        self
            .sheet(isPresented: showingPhotoPicker) {
                PhotoPickerRepresentable { results in
                    Task {
                        await BudgetAttachmentHelper.loadPhotos(
                            from: results, attachments: attachments, month: month, year: year
                        )
                    }
                }
            }
            .fileImporter(
                isPresented: showingFilePicker,
                allowedContentTypes: [.pdf, .text, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        BudgetAttachmentHelper.loadDocument(
                            from: url, attachments: attachments, month: month, year: year
                        )
                    }
                case .failure(let error):
                    print("❌ Error selecting file: \(error)")
                }
            }
    }
}

// MARK: - File Utilities (shared by all attachment views in this file)

func fileNameWithoutExtension(_ fileName: String) -> String {
    let components = fileName.components(separatedBy: ".")
    if components.count > 1 {
        return components.dropLast().joined(separator: ".")
    }
    return fileName
}

/// Loads UIImage data from a single PHPickerResult and calls `onImage` with JPEG data on success.
/// Does nothing if the result cannot provide a UIImage.
func loadImageData(from result: PHPickerResult, onImage: @escaping (Data) -> Void) {
    guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { return }
    result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
        if let error = error { print("❌ Error loading image: \(error)"); return }
        guard let image = object as? UIImage,
              let data = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to data")
            return
        }
        onImage(data)
    }
}

/// Reads file data from a security-scoped URL.
/// Returns (data, fileName, fileType) on success, or nil on failure.
func loadFileData(from url: URL) -> (data: Data, fileName: String, fileType: AttachmentType)? {
    guard url.startAccessingSecurityScopedResource() else {
        print("❌ Failed to access security-scoped resource")
        return nil
    }
    defer { url.stopAccessingSecurityScopedResource() }
    do {
        let data = try Data(contentsOf: url)
        let fileType = UTType(filenameExtension: url.pathExtension)
            .map { AttachmentType.fromUTType($0.identifier) } ?? .other
        return (data, url.lastPathComponent, fileType)
    } catch {
        print("❌ Error loading document: \(error)")
        return nil
    }
}

private func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Attachment Management View

/// Displays a section with income attachments, only visible when attachments exist.
/// Each attachment shows as a row with tap-to-view and context menu delete actions.
/// Delete confirmations are handled via an alert with primary tint.

struct AttachmentManagementView: View {
    @Binding var attachments: [Attachment]
    @Binding var attachmentToView: Attachment?
    @State private var showingDeleteConfirmation = false
    @State private var attachmentToDelete: Attachment?
    @State private var showingRenameAlert = false
    @State private var attachmentToRename: Attachment?
    @State private var renameText = ""
    @AppStorage("showFooters") private var showFooters: Bool = true

    var body: some View {
        if !attachments.isEmpty {
            Section {
                ForEach(attachments) { attachment in
                    AttachmentRowView(attachment: attachment) {
                        attachmentToView = attachment
                    } onRename: {
                        attachmentToRename = attachment
                        renameText = fileNameWithoutExtension(attachment.fileName)
                        showingRenameAlert = true
                    } onDelete: {
                        attachmentToDelete = attachment
                        showingDeleteConfirmation = true
                    }
                }
                .onMove { from, to in
                    attachments.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("Attachments")
            } footer: {
                if showFooters {
                    Text("Swipe right on an attachment to rename it, or left to delete it.")
                }
            }
            .attachmentDeleteAlert(
                isPresented: $showingDeleteConfirmation,
                fileName: attachmentToDelete.map { fileNameWithoutExtension($0.fileName) }
            ) {
                if let attachmentToDelete = attachmentToDelete,
                   let index = attachments.firstIndex(where: { $0.id == attachmentToDelete.id }) {
                    attachments.remove(at: index)
                }
            }
            .renameAttachmentAlert(
                isPresented: $showingRenameAlert,
                renameText: $renameText
            ) { trimmed in
                guard let target = attachmentToRename,
                      let index = attachments.firstIndex(where: { $0.id == target.id }) else { return }
                let ext = target.fileName.contains(".")
                    ? "." + target.fileName.components(separatedBy: ".").last!
                    : ""
                attachments[index].fileName = trimmed + ext
                attachmentToRename = nil
            }
        }
    }
}

// MARK: - Budget Attachment Management View

/// Displays budget attachments in a section with optional always-show behavior and selection mode.
/// - When empty and alwaysShow is false: section is hidden
/// - When empty and alwaysShow is true: shows "No Attachments Added" placeholder
/// - Selection mode: displays checkmark circles for multi-select with custom highlight color
/// - Normal mode: tap-to-view with context menu delete
/// Delete confirmations use AlertContainer to ensure primary tint on alert buttons.

struct BudgetAttachmentManagementView: View {
    @Binding var attachments: [BudgetAttachment]
    @Binding var attachmentToView: BudgetAttachment?
    var alwaysShow: Bool = false
    var isSelecting: Bool = false
    @Binding var selectedAttachments: Set<UUID>
    var highlightColor: Color = .blue
    var onToggleSelection: ((BudgetAttachment) -> Void)?
    @State private var showingDeleteConfirmation = false
    @State private var attachmentToDelete: BudgetAttachment?
    @State private var showingRenameAlert = false
    @State private var attachmentToRename: BudgetAttachment?
    @State private var renameText = ""
    @AppStorage("showFooters") private var showFooters: Bool = true

    var body: some View {
        if !attachments.isEmpty || alwaysShow {
            Section {
                if attachments.isEmpty {
                    // Show placeholder when no attachments
                    Text("No Attachments Added")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(attachments) { attachment in
                        BudgetAttachmentRowView(
                            attachment: attachment,
                            isSelecting: isSelecting,
                            isSelected: selectedAttachments.contains(attachment.id),
                            highlightColor: highlightColor,
                            onView: {
                                attachmentToView = attachment
                            },
                            onRename: {
                                attachmentToRename = attachment
                                renameText = fileNameWithoutExtension(attachment.fileName)
                                showingRenameAlert = true
                            },
                            onDelete: {
                                attachmentToDelete = attachment
                                showingDeleteConfirmation = true
                            },
                            onToggleSelection: {
                                onToggleSelection?(attachment)
                            }
                        )
                    }
                    .onMove(perform: isSelecting ? nil : { from, to in
                        attachments.move(fromOffsets: from, toOffset: to)
                    })
                }
            } header: {
                Text("Attachments")
                    .fontWeight(.medium)
                    .textCase(nil)
            } footer: {
                if showFooters {
                    Text("Swipe right on an attachment to rename it, or left to delete it.")
                }
            }
            .attachmentDeleteAlert(
                isPresented: $showingDeleteConfirmation,
                fileName: attachmentToDelete.map { fileNameWithoutExtension($0.fileName) }
            ) {
                if let attachmentToDelete = attachmentToDelete,
                   let index = attachments.firstIndex(where: { $0.id == attachmentToDelete.id }) {
                    attachments.remove(at: index)
                }
            }
            .renameAttachmentAlert(
                isPresented: $showingRenameAlert,
                renameText: $renameText
            ) { trimmed in
                guard let target = attachmentToRename,
                      let index = attachments.firstIndex(where: { $0.id == target.id }) else { return }
                let ext = target.fileName.contains(".")
                    ? "." + target.fileName.components(separatedBy: ".").last!
                    : ""
                attachments[index].fileName = trimmed + ext
                attachmentToRename = nil
            }
        }
    }
}
// MARK: - Budget Attachment Helper

/// Static utility methods for loading photos and documents into budget attachments.
/// These methods handle the complexity of PHPickerResult conversion and file loading
/// while associating attachments with a specific month and year for budget tracking.
/// - loadPhotos: Asynchronously converts PHPickerResult images to JPEG data and creates BudgetAttachments
/// - loadDocument: Loads file data from security-scoped URLs and determines file type from extension

struct BudgetAttachmentHelper {
    static func loadPhotos(from results: [PHPickerResult], attachments: Binding<[BudgetAttachment]>, month: Int, year: Int, onComplete: (() -> Void)? = nil) async {
        for result in results {
            loadImageData(from: result) { data in
                let attachment = BudgetAttachment(data: data, fileName: makePhotoFileName(), fileType: .image, month: month, year: year)
                Task { @MainActor in
                    attachments.wrappedValue.append(attachment)
                    onComplete?()
                }
            }
        }
    }
    
    static func loadDocument(from url: URL, attachments: Binding<[BudgetAttachment]>, month: Int, year: Int, onComplete: (() -> Void)? = nil) {
        guard let (data, fileName, fileType) = loadFileData(from: url) else { return }
        let attachment = BudgetAttachment(data: data, fileName: fileName, fileType: fileType, month: month, year: year)
        attachments.wrappedValue.append(attachment)
        onComplete?()
    }
}

// MARK: - Attachment Row View

/// Individual row view for displaying an attachment in a list.
/// Shows filename (without extension).
/// - Tap: triggers onView callback to open the attachment viewer
/// - Context menu: provides delete option with destructive styling

struct AttachmentRowView: View {
    let attachment: Attachment
    let onView: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            onView()
        } label: {
            HStack {
                Text(fileNameWithoutExtension(attachment.fileName))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onRename) {
                Image(systemName: "pencil")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .tint(.red)
        }
    }
}

// MARK: - Budget Attachment Row View

/// Row view for budget attachments with support for selection mode.
/// In selection mode: shows checkmark circles (filled when selected) in the custom highlight color
/// In normal mode: shows just the filename with tap-to-view and context menu delete
/// Uses conditional view modifier (.if) to only apply context menu when not in selection mode.

struct BudgetAttachmentRowView: View {
    let attachment: BudgetAttachment
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var highlightColor: Color = .blue
    let onView: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    var onToggleSelection: (() -> Void)?

    @State private var isHighlighted = false

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                SelectionIndicator(isSelected: isSelected, highlightColor: highlightColor)
                    .padding(.trailing, 12)
            }

            Text(fileNameWithoutExtension(attachment.fileName))
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isHighlighted ? highlightColor : .primary)
                .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelection?()
            } else {
                onView()
            }
        }
        .if(!isSelecting) { view in
            view
                .contextMenu {
                    Button(action: onRename) {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(action: onRename) {
                        Image(systemName: "pencil")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
        }
        .animation(.default, value: isHighlighted)
        .onReceive(NotificationCenter.default.publisher(for: .highlightNewItem)) { notification in
            guard let id = notification.object as? UUID, id == attachment.id else { return }
            isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isHighlighted = false
            }
        }
    }
}


// MARK: - Attachment Viewer Sheet

/// Full-screen viewer for income attachments presented as a sheet.
/// Supports different viewing modes based on file type:
/// - Images: Displays in a scrollable view with scaledToFit
/// - PDFs: Uses PDFViewerRepresentable for native PDF viewing
/// - Other files: Shows file icon, name, type, and formatted size
/// Toolbar provides share button (leading) and done button (trailing).
/// Sharing creates a temporary file and presents ShareSheet (UIActivityViewController).

struct AttachmentViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: Attachment
    @State private var shareItem: ShareItem?
    
    var body: some View {
        NavigationStack {
            Group {
                if attachment.fileType == .image {
                    if let uiImage = UIImage(data: attachment.data) {
                        ScrollView {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        }
                    } else {
                        Text("Unable to load image")
                            .foregroundStyle(.secondary)
                    }
                } else if attachment.fileType == .pdf {
                    PDFViewerRepresentable(data: attachment.data)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: attachment.fileType.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Text(fileNameWithoutExtension(attachment.fileName))
                            .font(.headline)
                        
                        Text(attachment.fileType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("File size: \(formatBytes(attachment.data.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle(fileNameWithoutExtension(attachment.fileName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        shareAttachment()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .tint(.primary)
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
    }
    
    private func shareAttachment() {
        if let url = prepareShareURL(fileName: attachment.fileName, data: attachment.data) {
            shareItem = ShareItem(url: url)
        }
    }
}

// MARK: - Budget Attachment Viewer Sheet

/// Full-screen viewer for budget attachments with editable filename functionality.
/// Features:
/// - Displays images, PDFs, or file info based on attachment type
/// - Editable filename in navigation title (tap to edit, uses CursorAtEndTextField_SwiftUI)
/// - Share button (when not editing) and done/cancel buttons in toolbar
/// - Tapping on content or scrolling cancels editing mode
/// - Validates filename (reverts to original if empty, only saves if changed)
/// - Tracks original filename to detect changes
/// - Updates binding array when filename is saved
/// - Synchronizes with external changes to the attachment via onChange

struct BudgetAttachmentViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var attachments: [BudgetAttachment]
    let attachment: BudgetAttachment
    @State private var shareItem: ShareItem?
    
    // Local state for editing
    @State private var fileName: String = ""
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFieldFocused: Bool
    
    // Track original value for change detection
    @State private var originalFileName: String = ""
    
    // Get the current version of the attachment from the binding
    private var currentAttachment: BudgetAttachment {
        attachments.first(where: { $0.id == attachment.id }) ?? attachment
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if currentAttachment.fileType == .image {
                    if let uiImage = UIImage(data: currentAttachment.data) {
                        ScrollView {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        }
                        .simultaneousGesture(
                            // Cancel editing when scrolling
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if isEditingTitle {
                                        cancelEditing()
                                    }
                                }
                        )
                    } else {
                        Text("Unable to load image")
                            .foregroundStyle(.secondary)
                    }
                } else if currentAttachment.fileType == .pdf {
                    PDFViewerRepresentable(data: currentAttachment.data)
                        .simultaneousGesture(
                            // Cancel editing when scrolling PDF
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if isEditingTitle {
                                        cancelEditing()
                                    }
                                }
                        )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: currentAttachment.fileType.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Text(fileNameWithoutExtension(currentAttachment.fileName))
                            .font(.headline)
                        
                        Text(currentAttachment.fileType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("File size: \(formatBytes(currentAttachment.data.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Cancel editing when tapping on the content area
                if isEditingTitle {
                    cancelEditing()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isEditingTitle {
                        CursorAtEndTextField_SwiftUI(
                            text: $fileName, 
                            placeholder: "File Name", 
                            onCommit: {
                                saveChanges()
                            },
                            toolbarDoneTriggersCommit: true
                        )
                            .multilineTextAlignment(.center)
                            .focused($isTitleFieldFocused)
                            .textInputAutocapitalization(.words)
                            .trimWhitespaceOnEditingEnd($fileName, isFocused: $isTitleFieldFocused)
                    } else {
                        Button {
                            startEditing()
                        } label: {
                            Text(fileNameWithoutExtension(currentAttachment.fileName))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .tint(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditingTitle {
                        Button {
                            cancelEditing()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .tint(.primary)
                    } else {
                        Button {
                            shareAttachment()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.primary)
                    }
                }
                

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditingTitle {
                        Button {
                            saveChanges()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.primary)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear {
            fileName = fileNameWithoutExtension(currentAttachment.fileName)
            originalFileName = fileNameWithoutExtension(currentAttachment.fileName)
        }
        .onChange(of: currentAttachment.fileName) { oldValue, newValue in
            // Update local state when the attachment changes in the binding
            if !isEditingTitle {
                fileName = fileNameWithoutExtension(newValue)
                originalFileName = fileNameWithoutExtension(newValue)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func startEditing() {
        isEditingTitle = true
        isTitleFieldFocused = true
    }
    
    private func cancelEditing() {
        fileName = originalFileName
        isEditingTitle = false
        isTitleFieldFocused = false
    }
    
    private func saveChanges() {
        // Trim whitespace
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespaces)
        
        // If empty, revert to original name
        if trimmedFileName.isEmpty {
            print("⏭️ BudgetAttachmentViewerSheet: Empty name, reverting to original")
            fileName = originalFileName
            isEditingTitle = false
            isTitleFieldFocused = false
            return
        }
        
        // Only save if there are actual changes
        guard trimmedFileName != originalFileName else {
            print("⏭️ BudgetAttachmentViewerSheet: No changes detected, skipping save")
            isEditingTitle = false
            isTitleFieldFocused = false
            return
        }
        
        // Find and update the attachment in the array
        if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
            var updatedAttachment = attachments[index]
            // Preserve the original file extension
            let fileExtension = getFileExtension(updatedAttachment.fileName)
            if !fileExtension.isEmpty {
                updatedAttachment.fileName = trimmedFileName + "." + fileExtension
            } else {
                updatedAttachment.fileName = trimmedFileName
            }
            attachments[index] = updatedAttachment
            
            // Update original value
            originalFileName = trimmedFileName
            fileName = trimmedFileName
            
            print("💾 BudgetAttachmentViewerSheet: Saved attachment name change")
        }
        
        isEditingTitle = false
        isTitleFieldFocused = false
    }
    
    private func shareAttachment() {
        if let url = prepareShareURL(fileName: currentAttachment.fileName, data: currentAttachment.data) {
            shareItem = ShareItem(url: url)
        }
    }

    private func getFileExtension(_ fileName: String) -> String {
        let components = fileName.components(separatedBy: ".")
        return components.count > 1 ? (components.last ?? "") : ""
    }
}


// MARK: - PDF Viewer (UIViewRepresentable)

/// UIViewRepresentable wrapper for PDFKit's PDFView.
/// Displays PDF documents with automatic scaling, single page continuous mode, and vertical scrolling.
/// Converts PDF data into a PDFDocument and displays it within the native PDFView component.

import PDFKit

struct PDFViewerRepresentable: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}

// MARK: - Share Sheet (UIViewControllerRepresentable)

/// UIViewControllerRepresentable wrapper for UIActivityViewController.
/// Presents the system share sheet for sharing files, URLs, and other content.
/// Used by attachment viewers to share attachment files via standard iOS sharing options.

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
// MARK: - Photo Picker (UIViewControllerRepresentable)

/// Privacy-friendly photo picker using PHPickerViewController.
/// Configuration:
/// - Filter: Images only (.images)
/// - Selection limit: Unlimited (0 = unlimited, users can select multiple photos)
/// - Asset representation: .current (gets actual image data without requiring library access)
/// - No photo library permissions required
/// Coordinator handles delegate callbacks and passes PHPickerResult array to completion handler.
struct PhotoPickerRepresentable: UIViewControllerRepresentable {
    let completion: ([PHPickerResult]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        
        // Only allow images
        configuration.filter = .images
        
        // Allow multiple selection (users can select multiple photos at once)
        configuration.selectionLimit = 0  // 0 = unlimited
        
        // Use the preferred asset representation mode for privacy
        // This ensures we get the actual image data without needing library access
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: ([PHPickerResult]) -> Void
        
        init(completion: @escaping ([PHPickerResult]) -> Void) {
            self.completion = completion
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            completion(results)
        }
    }
}

