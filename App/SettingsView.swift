import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager

    var body: some View {
        Form {
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
