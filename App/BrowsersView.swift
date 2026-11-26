import AppKit
import NetworkExtension
import SwiftUI

/// Browser filtering: HTTPS of the chosen browsers is decrypted on this Mac with a local root CA
/// so browser lists (paths, cosmetic rules, scriptlets) can apply. Other apps are never touched.
struct BrowsersView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var trustError: String?
    @State private var trusted = false

    private var certificate: Data? { tunnel.status?.certificate }

    var body: some View {
        Form {
            Section {
                Toggle("Filter ads inside browsers", isOn: $store.settings.https.enabled)
                Text("Browsers' HTTPS connections are decrypted on this Mac, filtered with the browser lists, and re-encrypted. Banking, payment and health sites are never decrypted, and no page content leaves your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if store.settings.https.enabled {
                Section("Certificate") { certificateRow }
                Section {
                    ForEach(KnownBrowser.all) { browser in
                        BrowserRow(browser: browser)
                    }
                } header: {
                    Text("Browsers")
                } footer: {
                    Text("Firefox uses the macOS certificate store only when security.enterprise_roots.enabled is on (the default on recent versions).")
                        .foregroundStyle(.secondary)
                }
                Section("Status") {
                    LabeledContent("Browser filtering", value: proxyState)
                    if let error = tunnel.browserProxyError {
                        Label {
                            Text("Could not start: \(error)")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        if tunnel.lastErrorNeedsSettings { VPNSettingsHelp() }
                    }
                    if let flows = tunnel.status?.browserFlows {
                        LabeledContent("Browser connections filtered", value: flows.formatted())
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Browsers")
        .onAppear(perform: checkTrust)
        .onChange(of: tunnel.status?.certificateFingerprint) { checkTrust() }
    }

    @ViewBuilder private var certificateRow: some View {
        if tunnel.state != .on {
            Text("Turn protection on: the filtering extension creates the certificate.")
                .foregroundStyle(.secondary)
        } else if let certificate {
            HStack {
                Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(trusted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trusted ? "Open AdBlock Local CA is trusted" : "The certificate is not trusted yet")
                    Text("SHA-256 \(CertificateTrust.fingerprint(certificate).prefix(16))…")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if trusted {
                    Button("Remove Trust", role: .destructive) {
                        CertificateTrust.remove(certificate)
                        store.settings.https.trustedCA = nil
                        checkTrust()
                    }
                } else {
                    Button("Trust Certificate…") { trust(certificate) }
                }
            }
            if let trustError {
                Text(trustError).font(.callout).foregroundStyle(.red)
            }
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text("Creating the certificate…").foregroundStyle(.secondary)
            }
        }
    }

    private var proxyState: String {
        switch tunnel.browserProxy {
        case .connected: "Running"
        case .connecting, .reasserting: "Starting…"
        case .disconnecting: "Stopping…"
        default:
            if tunnel.browserProxyError != nil { "Failed" }
            else { trusted ? "Off" : "Waiting for the trusted certificate" }
        }
    }

    private func checkTrust() {
        guard let certificate else {
            trusted = false
            return
        }
        trusted = CertificateTrust.isTrusted(certificate)
        let fingerprint = CertificateTrust.fingerprint(certificate)
        // Record the verified CA, or forget one the user removed in Keychain Access.
        if trusted, store.settings.https.trustedCA != fingerprint {
            store.settings.https.trustedCA = fingerprint
        } else if !trusted, store.settings.https.trustedCA == fingerprint {
            store.settings.https.trustedCA = nil
        }
    }

    private func trust(_ certificate: Data) {
        do {
            try CertificateTrust.install(certificate)
            trustError = nil
        } catch {
            trustError = "macOS did not save the trust setting (\(error.localizedDescription)). Keychain Access opens instead: double-click “\(CertificateTrust.label)”, expand Trust and choose Always Trust."
            try? CertificateTrust.openInKeychainAccess(certificate)
        }
        checkTrust()
    }
}

private struct BrowserRow: View {
    @EnvironmentObject private var store: SettingsStore
    let browser: KnownBrowser

    private var installed: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) != nil
    }

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { store.settings.https.browsers.contains(browser.id) },
                set: { store.setBrowser(browser.id, enabled: $0) })
        ) {
            HStack {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 20, height: 20)
                }
                Text(browser.name)
                if !installed {
                    Text("not installed").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
