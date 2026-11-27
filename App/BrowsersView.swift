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

    private var tint: Color { SidebarItem.browsers.tint }

    var body: some View {
        form
            .pageBackground()
            .navigationTitle("Browsers")
            .navigationSubtitle(store.settings.https.enabled ? "Filtering: \(proxyState)" : "In-page ad filtering is off")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle("Filter ads inside browsers", isOn: $store.settings.https.enabled)
                        .toggleStyle(.switch)
                        .help("Filter ads inside browsers")
                }
            }
        .onAppear(perform: checkTrust)
        .onChange(of: tunnel.status?.certificateFingerprint) { checkTrust() }
    }

    private var form: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemName: "lock.shield.fill", tint: tint, size: 30)
                    Text("Browsers' HTTPS connections are decrypted on this Mac, filtered with the browser lists, and re-encrypted. Banking, payment and health sites are never decrypted, and no page content leaves your Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if store.settings.https.enabled {
                Section {
                    certificateRow
                } header: {
                    SectionLabel("Certificate", icon: "checkmark.seal.fill", tint: Theme.accent)
                }
                Section {
                    ForEach(KnownBrowser.all) { browser in
                        BrowserRow(browser: browser)
                    }
                } header: {
                    SectionLabel("Browsers", icon: "macwindow.on.rectangle", tint: tint)
                } footer: {
                    Text("Firefox uses the macOS certificate store only when security.enterprise_roots.enabled is on (the default on recent versions).")
                        .foregroundStyle(.secondary)
                }
                Section {
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
                } header: {
                    SectionLabel("Status", icon: "waveform.path.ecg", tint: Theme.info)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var certificateRow: some View {
        if tunnel.state != .on {
            Text("Turn protection on: the filtering extension creates the certificate.")
                .foregroundStyle(.secondary)
        } else if let certificate {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    tint: trusted ? Theme.accent : Theme.warning, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trusted ? "Open AdBlock Local CA is trusted" : "The certificate is not trusted yet")
                        .fontWeight(.medium)
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
                        .buttonStyle(.borderedProminent)
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
        let fingerprint = CertificateTrust.fingerprint(certificate)
        // Show the last verified answer at once; trust evaluation can block (Apple advises
        // against it on the main thread), so the fresh answer comes from a background task.
        trusted = store.settings.https.trustedCA == fingerprint
        Task {
            let isTrusted = await Task.detached(priority: .userInitiated) {
                CertificateTrust.isTrusted(certificate)
            }.value
            guard self.certificate == certificate else { return }
            trusted = isTrusted
            // Record the verified CA, or forget one the user removed in Keychain Access.
            if isTrusted, store.settings.https.trustedCA != fingerprint {
                store.settings.https.trustedCA = fingerprint
            } else if !isTrusted, store.settings.https.trustedCA == fingerprint {
                store.settings.https.trustedCA = nil
            }
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
    @State private var icon: NSImage?
    @State private var installed = true

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { store.settings.https.browsers.contains(browser.id) },
                set: { store.setBrowser(browser.id, enabled: $0) })
        ) {
            HStack {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                }
                Text(browser.name)
                if !installed {
                    Pill(text: "Not installed", tint: Theme.slate)
                }
            }
        }
        .toggleStyle(.switch)
        // Looked up once per appearance, not on every redraw (the status redraws this view every
        // two seconds while protection is on).
        .onAppear {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id)
            installed = url != nil
            icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }
}
