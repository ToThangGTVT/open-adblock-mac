import Foundation
import SwiftUI

/// The user's settings, kept in the app's own storage. Every saved change goes to the tunnel
/// (which owns the filter list downloads) through `onChange`.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            // @Published re-enters didSet for the revision write below; comparing without the
            // revision stops that second pass (and ignores writes that change nothing).
            var unchanged = settings
            unchanged.revision = oldValue.revision
            guard unchanged != oldValue else { return }
            settings.revision = Date()
            try? settings.save()
            onChange?(settings)
        }
    }

    /// Called after every saved change (the app wires it to `TunnelManager.apply`).
    var onChange: ((Settings) -> Void)?

    init() {
        settings = Settings.load()
    }

    func setList(_ id: String, enabled: Bool) {
        guard let index = settings.lists.firstIndex(where: { $0.id == id }) else { return }
        settings.lists[index].enabled = enabled
    }

    func add(_ list: FilterListSetting) {
        guard !settings.lists.contains(where: { $0.id == list.id || $0.url == list.url }) else { return }
        settings.lists.append(list)
    }

    func remove(_ id: String) {
        settings.lists.removeAll { $0.id == id }
    }

    func setBrowser(_ id: String, enabled: Bool) {
        var browsers = settings.https.browsers.filter { $0 != id }
        if enabled { browsers.append(id) }
        settings.https.browsers = browsers
    }
}
