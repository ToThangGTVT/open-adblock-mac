import SwiftUI

@main
struct OpenAdBlockApp: App {
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var store = SettingsStore()
    @StateObject private var installer = ExtensionInstaller()
    @StateObject private var catalogs = CatalogStore()

    var body: some Scene {
        WindowGroup("Open AdBlock", id: "main") {
            ContentView()
                .environmentObject(tunnel)
                .environmentObject(store)
                .environmentObject(installer)
                .environmentObject(catalogs)
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
        } label: {
            Image(systemName: tunnel.state.isOn ? "shield.lefthalf.filled" : "shield.slash")
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore
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
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
