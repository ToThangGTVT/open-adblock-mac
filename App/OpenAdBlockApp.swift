import SwiftUI

@main
struct OpenAdBlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var store = SettingsStore()
    @StateObject private var installer = ExtensionInstaller()
    @StateObject private var catalogs = CatalogStore()
    @StateObject private var updater = Updater()
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some Scene {
        WindowGroup("Open AdBlock", id: "main") {
            ContentView()
                .environmentObject(tunnel)
                .environmentObject(store)
                .environmentObject(installer)
                .environmentObject(catalogs)
                .environmentObject(updater)
                .environmentObject(launchAtLogin)
                .frame(minWidth: 760, minHeight: 520)
                .task {
                    store.onChange = { tunnel.apply($0) }
                    tunnel.apply(store.settings)
                    // Installs or updates the bundled system extension on every launch.
                    installer.activate()
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(tunnel)
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            Image(systemName: tunnel.state.isOn ? "shield.lefthalf.filled" : "shield.slash")
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(tunnel.state.isOn ? "Protection is on" : "Protection is off")
        if let status = tunnel.status, tunnel.state == .on {
            Text("\(status.todayBlocked.formatted()) blocked today")
        }
        Divider()
        Button(tunnel.state.isOn ? "Turn Off" : "Turn On") {
            tunnel.setEnabled(!tunnel.state.isOn, settings: store.settings)
        }
        Button("Open Open AdBlock") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if updater.isConfigured {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
