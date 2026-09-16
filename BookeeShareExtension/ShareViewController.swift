//
//  ShareViewController.swift
//  BookeeShareExtension
//
//  Entry point for the Share Extension. Reads the budget list from the shared
//  App Group, hosts ShareView, and saves incoming files to the pending queue.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let appGroupID = "group.KaraCoding.Bookee"
    private var addTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let defaults = UserDefaults(suiteName: appGroupID)

        // Read the budget list written by the main app on each .active transition.
        let budgets: [(name: String, timestamp: Double)] = (defaults?
            .array(forKey: "budgetList") as? [[String: Any]])?
            .compactMap { dict in
                guard let name = dict["name"] as? String,
                      let ts   = dict["timestamp"] as? Double else { return nil }
                return (name, ts)
            } ?? []

        let pinnedTimestamp = defaults?.double(forKey: "pinnedBudgetTimestamp") ?? 0

        let host = UIHostingController(rootView: ShareView(
            budgets: budgets,
            pinnedTimestamp: pinnedTimestamp,
            onAdd: { [weak self] budgetTs, month, year in
                self?.handleAdd(budgetTimestamp: budgetTs, month: month, year: year)
            },
            onCancel: { [weak self] in self?.handleCancel() }
        ))

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func handleCancel() {
        addTask?.cancel()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func handleAdd(budgetTimestamp: Double, month: Int, year: Int) {
        addTask = Task {
            await processAndSave(budgetTimestamp: budgetTimestamp, month: month, year: year)
            guard !Task.isCancelled else { return }
            extensionContext?.completeRequest(returningItems: [])
        }
    }

    // MARK: - Attachment Processing

    private func processAndSave(budgetTimestamp: Double, month: Int, year: Int) async {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        var pending: [[String: Any]] = []
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if let entry = await loadAttachment(
                    from: provider, budgetTimestamp: budgetTimestamp, month: month, year: year
                ) {
                    pending.append(entry)
                }
            }
        }

        guard !pending.isEmpty else { return }

        if let defaults = UserDefaults(suiteName: appGroupID) {
            var queue = (defaults.array(forKey: "pendingSharedAttachments") as? [[String: Any]]) ?? []
            queue.append(contentsOf: pending)
            defaults.set(queue, forKey: "pendingSharedAttachments")
            defaults.synchronize()
        }
    }

    private func loadAttachment(
        from provider: NSItemProvider,
        budgetTimestamp: Double,
        month: Int,
        year: Int
    ) async -> [String: Any]? {
        // Images (Photos app, screenshots)
        if provider.canLoadObject(ofClass: UIImage.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let self,
                          let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.8) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let id = UUID().uuidString
                    if self.saveFile(data: data, id: id) {
                        continuation.resume(returning: [
                            "id": id,
                            "fileName": "Photo_\(id).jpg",
                            "fileType": "image",
                            "month": month,
                            "year": year,
                            "budgetTimestamp": budgetTimestamp,
                        ])
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        // PDFs and other files (Files app, Mail, etc.)
        for typeID in [UTType.pdf.identifier, UTType.data.identifier, UTType.fileURL.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: typeID, options: nil) { [weak self] item, _ in
                    guard let self else { continuation.resume(returning: nil); return }
                    var data: Data?
                    var fileName = "File"
                    if let url = item as? URL {
                        _ = url.startAccessingSecurityScopedResource()
                        fileName = url.lastPathComponent
                        data = try? Data(contentsOf: url)
                        url.stopAccessingSecurityScopedResource()
                    } else if let rawData = item as? Data {
                        data = rawData
                        if typeID == UTType.pdf.identifier { fileName = "Document.pdf" }
                    }
                    guard let data else { continuation.resume(returning: nil); return }
                    let ext = (fileName as NSString).pathExtension.lowercased()
                    let fileType = ext == "pdf" ? "pdf" : "other"
                    let id = UUID().uuidString
                    if self.saveFile(data: data, id: id) {
                        continuation.resume(returning: [
                            "id": id,
                            "fileName": fileName,
                            "fileType": fileType,
                            "month": month,
                            "year": year,
                            "budgetTimestamp": budgetTimestamp,
                        ])
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - File I/O

    private func saveFile(data: Data, id: String) -> Bool {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return false
        }
        let dir = base.appendingPathComponent("PendingAttachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try? data.write(to: dir.appendingPathComponent(id))) != nil
    }
}
