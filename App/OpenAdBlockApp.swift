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
            MenuBarPanel()
                .environmentObject(tunnel)
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            Image(systemName: tunnel.state.isOn ? "shield.lefthalf.filled" : "shield.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar panel: protection at a glance, with its switch.
private struct MenuBarPanel: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var updater: Updater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tunnel.state.fill)
                        .frame(width: 44, height: 44)
                    Image(systemName: tunnel.state.isOn ? "lock.shield.fill" : "shield.slash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tunnel.state.title).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(tunnel.state.isOn ? "Every app on this Mac is filtered" : "Ads and trackers can get through")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle(
                    "Protection",
                    isOn: Binding(
                        get: { tunnel.state.isOn }, set: { tunnel.setEnabled($0, settings: store.settings) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(tunnel.state == .loading || tunnel.state == .disconnecting)
            }

            if let status = tunnel.status, tunnel.state == .on {
                HStack(spacing: 10) {
                    tile("hand.raised.fill", Theme.blocked, status.todayBlocked.formatted(), "Blocked today")
                    tile("network", Theme.info, status.todayTotal.formatted(), "Requests today")
                }
            }

            Divider()

            VStack(spacing: 2) {
                row("Open Open AdBlock", icon: "macwindow") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                }
                if updater.isConfigured {
                    row("Check for Updates…", icon: "arrow.down.circle") {
                        updater.checkForUpdates()
                        dismiss()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
                row("Quit Open AdBlock", icon: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .animation(.easeInOut(duration: 0.3), value: tunnel.state)
    }

    private func tile(_ icon: String, _ tint: Color, _ value: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, icon: icon, action: action)
    }
}

private struct MenuRow: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Color.primary.opacity(hovering && isEnabled ? 0.08 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}
