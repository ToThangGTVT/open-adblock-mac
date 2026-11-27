import ServiceManagement
import SwiftUI

/// Starts the app when the user logs in, through the system's Login Items (System Settings ›
/// General › Login Items). The system owns the state, so it is read back instead of stored.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var enabled = false
    /// macOS registered the item but the user switched it off in System Settings.
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?

    init() { refresh() }

    /// Reads the state off the main thread: it is an XPC round trip to the system, which would
    /// otherwise stall the window (opening Settings, or the app becoming active).
    func refresh() {
        Task {
            let status = await Task.detached(priority: .userInitiated) { SMAppService.mainApp.status }.value
            apply(status)
        }
    }

    private func apply(_ status: SMAppService.Status) {
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        apply(SMAppService.mainApp.status)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
