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
}
