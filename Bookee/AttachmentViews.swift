//
//  AttachmentViews.swift
//  Bookee
//
//  Created by Kara Eveland on 2/14/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Share URL Helper

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

// MARK: - File Utilities

func fileNameWithoutExtension(_ fileName: String) -> String {
    let components = fileName.components(separatedBy: ".")
    return components.count > 1 ? components.dropLast().joined(separator: ".") : fileName
}

func loadImageData(from result: PHPickerResult, onImage: @escaping (Data) -> Void) {
    guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { return }
    result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
        if let error { print("❌ Error loading image: \(error)"); return }
        guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.8) else { return }
        onImage(data)
    }
}

func loadFileData(from url: URL) -> (data: Data, fileName: String, fileType: AttachmentType)? {
    guard url.startAccessingSecurityScopedResource() else { return nil }
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
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Delete Alert Modifier

extension View {
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
                        Button("Delete", role: .destructive) { onDelete() }
                    } message: {
                        if let fileName { Text("This will permanently delete '\(fileName)'. This action cannot be undone.") }
                    }
            }
        }
    }
}

// MARK: - Attachment Pickers Modifier

extension View {
    /// Attaches a photo-picker sheet and file-importer for generic attachments.
    func attachmentPickers(
        showingPhotoPicker: Binding<Bool>,
        showingFilePicker: Binding<Bool>,
        attachments: Binding<[Attachment]>
    ) -> some View {
        self
            .sheet(isPresented: showingPhotoPicker) {
                PhotoPickerRepresentable { results in
                    for result in results {
                        loadImageData(from: result) { data in
                            let attachment = Attachment(data: data, fileName: makePhotoFileName(), fileType: .image)
                            Task { @MainActor in
                                attachments.wrappedValue.append(attachment)
                            }
                        }
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
                    if let url = urls.first, let (data, fileName, fileType) = loadFileData(from: url) {
                        let attachment = Attachment(data: data, fileName: fileName, fileType: fileType)
                        attachments.wrappedValue.append(attachment)
                    }
                case .failure(let error):
                    print("❌ Error selecting file: \(error)")
                }
            }
    }
}

// MARK: - Attachment Management View

/// Displays a section with attachments, only visible when attachments exist.
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
                .onMove { from, to in attachments.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("Attachments")
            } footer: {
                if showFooters { Text("Swipe right on an attachment to rename it, or left to delete it.") }
            }
            .attachmentDeleteAlert(
                isPresented: $showingDeleteConfirmation,
                fileName: attachmentToDelete.map { fileNameWithoutExtension($0.fileName) }
            ) {
                if let target = attachmentToDelete,
                   let index = attachments.firstIndex(where: { $0.id == target.id }) {
                    attachments.remove(at: index)
                }
            }
            .renameAttachmentAlert(isPresented: $showingRenameAlert, renameText: $renameText) { trimmed in
                guard let target = attachmentToRename,
                      let index = attachments.firstIndex(where: { $0.id == target.id }) else { return }
                let ext = target.fileName.contains(".") ? "." + (target.fileName.components(separatedBy: ".").last ?? "") : ""
                attachments[index].fileName = trimmed + ext
                attachmentToRename = nil
            }
        }
    }
}

// MARK: - Attachment Row View

struct AttachmentRowView: View {
    let attachment: Attachment
    let onView: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button { onView() } label: {
            HStack {
                Image(systemName: attachment.fileType.icon)
                    .foregroundStyle(.secondary)
                Text(fileNameWithoutExtension(attachment.fileName))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onRename) { Image(systemName: "pencil") }.tint(.indigo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onDelete) { Image(systemName: "trash") }.tint(.red)
        }
    }
}

// MARK: - Attachment Viewer Sheet

/// Full-screen viewer for attachments presented as a sheet.
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
                            Image(uiImage: uiImage).resizable().scaledToFit()
                        }
                    } else {
                        Text("Unable to load image").foregroundStyle(.secondary)
                    }
                } else if attachment.fileType == .pdf {
                    PDFViewerRepresentable(data: attachment.data)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: attachment.fileType.icon)
                            .font(.system(size: 60)).foregroundStyle(.blue)
                        Text(fileNameWithoutExtension(attachment.fileName)).font(.headline)
                        Text(attachment.fileType.displayName).font(.subheadline).foregroundStyle(.secondary)
                        Text("File size: \(formatBytes(attachment.data.count))").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle(fileNameWithoutExtension(attachment.fileName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { shareAttachment() } label: { Label("Share", systemImage: "square.and.arrow.up") }.tint(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }.tint(.primary)
                }
            }
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    private func shareAttachment() {
        if let url = prepareShareURL(fileName: attachment.fileName, data: attachment.data) {
            shareItem = ShareItem(url: url)
        }
    }
}

// MARK: - PDF Viewer

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
        if let document = PDFDocument(data: data) { pdfView.document = document }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Photo Picker

struct PhotoPickerRepresentable: UIViewControllerRepresentable {
    let completion: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: ([PHPickerResult]) -> Void
        init(completion: @escaping ([PHPickerResult]) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            completion(results)
        }
    }
}
