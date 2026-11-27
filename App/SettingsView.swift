import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var updater: Updater
    @AppStorage(DockIcon.hiddenKey) private var hideDockIcon = true
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.enabled }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Allow Open AdBlock in Login Items to start it at login.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.error {
                    Text(error).foregroundStyle(.red)
                }
                Toggle("Hide from Dock", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, hidden in DockIcon.apply(hidden: hidden) }
            } header: {
                Text("App")
            } footer: {
                Text("Open AdBlock stays in the menu bar. Closing the window keeps protection running.")
                    .foregroundStyle(.secondary)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // The user may have changed Login Items in System Settings meanwhile.
                launchAtLogin.refresh()
            }

            Section("DNS") {
                Picker("Upstream", selection: $store.settings.dns) {
                    ForEach(DNSPreset.allCases) { Text($0.title).tag($0) }
                }
                if store.settings.dns == .custom {
                    Picker("Protocol", selection: $store.settings.customUpstream.protocol) {
                        ForEach(Upstream.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Server IP", text: $store.settings.customUpstream.ip)
                    if [.tls, .https, .quic].contains(store.settings.customUpstream.protocol) {
                        TextField("Server name (TLS)", text: $store.settings.customUpstream.serverName)
                    }
                    if store.settings.customUpstream.protocol == .https {
                        TextField("Path", text: $store.settings.customUpstream.path)
                    }
                }
                Picker("Blocked domains answer", selection: $store.settings.blockMode) {
                    Text("0.0.0.0 / ::").tag("zero")
                    Text("NXDOMAIN").tag("nxdomain")
                }
            }

            Section {
                Toggle("Filter IPv6 traffic", isOn: $store.settings.ipv6)
                Toggle("Keep the query log", isOn: $store.settings.logging)
                Toggle("Goodbye DPI (experimental)", isOn: $store.settings.dpi)
            } header: {
                Text("Traffic")
            } footer: {
                Text("Goodbye DPI splits and disguises the first packets of HTTP/HTTPS connections so that network censorship based on deep packet inspection cannot read them.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    .disabled(!updater.isConfigured)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text(updater.isConfigured
                    ? "New versions come from the project's GitHub releases."
                    : "This build has no update key, so it cannot update itself.")
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: Bundle.main.version)
                LabeledContent("Core", value: tunnel.status?.engineVersion ?? "Starts with protection")
                Link("Source code", destination: URL(string: "https://github.com/ToThangGTVT/open-adblock-mac")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

extension Bundle {
    var version: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
