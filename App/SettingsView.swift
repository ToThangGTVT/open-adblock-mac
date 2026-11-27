import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var updater: Updater
    @AppStorage(DockIcon.hiddenKey) private var hideDockIcon = true
    @EnvironmentObject private var launchAtLogin: LaunchAtLogin

    var body: some View {
        form
            .pageBackground()
            .navigationTitle("Settings")
            .navigationSubtitle("Version \(Bundle.main.version)")
    }

    private var form: some View {
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
                SectionLabel("App", icon: "app.badge.checkmark.fill", tint: Theme.accent)
            } footer: {
                Text("Open AdBlock stays in the menu bar. Closing the window keeps protection running.")
                    .foregroundStyle(.secondary)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // The user may have changed Login Items in System Settings meanwhile.
                launchAtLogin.refresh()
            }

            Section {
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
            } header: {
                SectionLabel("Secure DNS", icon: "lock.fill", tint: Theme.info)
            } footer: {
                Text("Encrypted DNS (HTTPS, TLS or QUIC) hides which sites you visit from your network and provider.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Filter IPv6 traffic", isOn: $store.settings.ipv6)
                Toggle("Keep the query log", isOn: $store.settings.logging)
                Toggle("Goodbye DPI (experimental)", isOn: $store.settings.dpi)
            } header: {
                SectionLabel("Traffic", icon: "arrow.left.arrow.right", tint: Theme.violet)
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
                SectionLabel("Updates", icon: "arrow.down.circle.fill", tint: Theme.warning)
            } footer: {
                Text(updater.isConfigured
                    ? "New versions come from the project's GitHub releases."
                    : "This build has no update key, so it cannot update itself.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open AdBlock").font(.headline)
                        Text("Free and open source. Filtering runs on this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(destination: URL(string: "https://github.com/ToThangGTVT/open-adblock-mac")!) {
                        Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                LabeledContent("App", value: Bundle.main.version)
                LabeledContent("Core", value: tunnel.status?.engineVersion ?? "Starts with protection")
            } header: {
                SectionLabel("About", icon: "info.circle.fill", tint: Theme.slate)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

extension Bundle {
    var version: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
