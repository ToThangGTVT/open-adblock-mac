import AppKit

/// Whether the app shows an icon in the Dock (and in the Command-Tab switcher). Hidden by default:
/// the app lives in the menu bar, and Info.plist sets `LSUIElement` so no icon flashes at launch.
enum DockIcon {
    /// UserDefaults key, also bound with `@AppStorage` in Settings.
    static let hiddenKey = "hideDockIcon"

    static var hidden: Bool {
        UserDefaults.standard.object(forKey: hiddenKey) as? Bool ?? true
    }

    /// Applies the stored preference.
    @MainActor
    static func apply() {
        apply(hidden: hidden)
    }

    @MainActor
    static func apply(hidden: Bool) {
        let policy: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Changing the policy deactivates the app and can send its window behind others; bring it
        // back on the next turn of the run loop.
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.apply()
        // An LSUIElement app is not brought to the front on launch; show the window the user asked for.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// With the Dock icon hidden, closing the window leaves the app in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
