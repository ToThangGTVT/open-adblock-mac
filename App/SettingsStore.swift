import Foundation
import SwiftUI

/// The user's settings plus filter list downloads. Saving writes the shared settings file and
/// asks a running tunnel to reload it.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            try? settings.save()
            onChange?()
        }
    }
    @Published private(set) var downloading: Set<String> = []
    @Published var downloadError: String?

    /// Called after every saved change (the app wires it to `TunnelManager.reload`).
    var onChange: (() -> Void)?

    init() {
        settings = Settings.load()
        try? settings.save()
    }

    func setList(_ id: String, enabled: Bool) {
        guard let index = settings.lists.firstIndex(where: { $0.id == id }) else { return }
        settings.lists[index].enabled = enabled
        if enabled, settings.lists[index].updated == nil { Task { await download(id) } }
    }

    /// Downloads enabled lists that were never fetched (first launch).
    func downloadMissing() async {
        for list in settings.lists where list.enabled && list.updated == nil {
            await download(list.id)
        }
    }

    func updateAll() async {
        for list in settings.lists where list.enabled { await download(list.id) }
    }

    func download(_ id: String) async {
        guard let list = FilterCatalog.list(id), !downloading.contains(id) else { return }
        downloading.insert(id)
        defer { downloading.remove(id) }
        do {
            let (data, response) = try await URLSession.shared.data(from: list.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            try data.write(to: AppGroup.listURL(id), options: .atomic)
            let text = String(decoding: data, as: UTF8.self)
            let rules = text.split(whereSeparator: \.isNewline).filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("#")
            }.count
            if let index = settings.lists.firstIndex(where: { $0.id == id }) {
                settings.lists[index].updated = Date()
                settings.lists[index].rules = rules
            }
            downloadError = nil
        } catch {
            downloadError = "\(list.name): \(error.localizedDescription)"
        }
    }
}
