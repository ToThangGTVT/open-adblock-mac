import AppKit
import Foundation
import NetworkExtension
import SwiftUI

/// Owns the VPN configuration and talks to the packet tunnel. Everything the UI shows about the
/// running engine comes from `status`, polled while the app is open.
@MainActor
final class TunnelManager: ObservableObject {
    enum State: Equatable {
        case loading, off, connecting, on, disconnecting
        case failed(String)

        var isOn: Bool { self == .on || self == .connecting }
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var status: TunnelStatus?
    @Published private(set) var lastError: String? {
        didSet { lastErrorNeedsSettings = false }
    }
    /// The last error is one the user resolves in System Settings › VPN & Filters (macOS
    /// refused to launch the extension, or the configuration is missing or broken).
    @Published private(set) var lastErrorNeedsSettings = false
    /// State of the browser transparent proxy (browser filtering).
    @Published private(set) var browserProxy: NEVPNStatus = .invalid
    /// Why browser filtering failed to start or stopped on its own, as macOS reported it.
    @Published private(set) var browserProxyError: String?

    /// Latest settings, for the browser proxy decision.
    private var settings = Settings.load()
    private var proxyManager: NETransparentProxyManager?
    private var proxyObserver: NSObjectProtocol?
    private var proxyWanted: Bool?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var poller: Task<Void, Never>?

    /// Whether protection was on when the app last quit; it turns on again at the next launch.
    private static let resumeKey = "resumeProtectionOnLaunch"

    init() {
        AppDelegate.beforeQuit = { [weak self] in await self?.stopForQuit() }
        Task { await load() }
    }

    /// The tunnel lives only as long as the app: quitting stops protection and browser filtering,
    /// and the next launch turns protection back on if it was on.
    private func stopForQuit() async {
        UserDefaults.standard.set(state.isOn, forKey: Self.resumeKey)
        let stopped: [NEVPNStatus] = [.disconnected, .invalid]
        let connections = [manager?.connection, proxyManager?.connection]
            .compactMap { $0 }
            .filter { !stopped.contains($0.status) }
        connections.forEach { $0.stopVPNTunnel() }
        // The stop request is asynchronous: wait (briefly) until macOS acts on it, so it is not
        // lost with the process.
        for _ in 0..<30 where !connections.allSatisfy({ stopped.contains($0.status) }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first { manager in
                (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                    == AppGroup.tunnelBundleIdentifier
            }
            observe()
            refreshState()
            if manager != nil, state == .off, UserDefaults.standard.bool(forKey: Self.resumeKey) {
                setEnabled(true, settings: settings)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool, settings: Settings) {
        self.settings = settings
        Task {
            do {
                if enabled { try await start(settings) } else { manager?.connection.stopVPNTunnel() }
            } catch {
                lastError = error.localizedDescription
                let nsError = error as NSError
                lastErrorNeedsSettings = nsError.domain == NEVPNErrorDomain
                    && [NEVPNError.configurationDisabled, .configurationInvalid, .configurationStale]
                        .contains { $0.rawValue == nsError.code }
                refreshState()
            }
        }
    }

    /// Hands changed settings to the running tunnel, and to the VPN configuration so the next
    /// start (also one the system triggers) uses them.
    func apply(_ settings: Settings) {
        // A browser filtering change is a fresh decision, and a new chance after a failed start.
        if settings.https != self.settings.https {
            proxyWanted = nil
            browserProxyError = nil
        }
        self.settings = settings
        Task {
            await send(.apply, settings: settings)
            if let manager, manager.connection.status != .invalid {
                _ = try? await configuredManager(settings)
            }
        }
    }

    func updateLists() { Task { await send(.updateLists) } }

    func clearLog() { Task { await send(.clearLog) } }

    private func start(_ settings: Settings) async throws {
        let manager = try await configuredManager(settings)
        try manager.connection.startVPNTunnel()
        lastError = nil
    }

    /// Creates the VPN configuration on first use; the system asks the user to allow it once.
    private func configuredManager(_ settings: Settings) async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = AppGroup.tunnelBundleIdentifier
        configuration.serverAddress = "Open AdBlock"
        configuration.disconnectOnSleep = false
        configuration.providerConfiguration = [AppGroup.settingsKey: settings.encoded()]
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "Open AdBlock"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        // Reload so the connection object reflects the saved configuration.
        try await manager.loadFromPreferences()
        if self.manager == nil {
            self.manager = manager
            observe()
        }
        return manager
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let manager else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    private func refreshState() {
        guard let manager else {
            state = .off
            stopPolling()
            return
        }
        let previous = state
        switch manager.connection.status {
        case .connected: state = .on
        case .connecting, .reasserting: state = .connecting
        case .disconnecting: state = .disconnecting
        case .invalid, .disconnected: state = .off
        @unknown default: state = .off
        }
        if state == .on {
            lastError = nil
        } else if state == .off, previous != .off, previous != .loading {
            // The system ends a tunnel that failed to start (or died) silently: ask it why.
            Self.disconnectReason(of: manager.connection) { [weak self] reason in
                guard let self, let reason, self.state == .off else { return }
                self.lastError = "Protection stopped: \(reason.message)"
                self.lastErrorNeedsSettings = reason.needsSettings
            }
        }
        if state == .on { startPolling() } else if state == .off { stopPolling() }
        syncBrowserProxy()
    }

    /// Browser filtering runs only while protection is on, the user enabled it and the root CA
    /// the extension holds is the one the app verified as trusted.
    private func syncBrowserProxy() {
        // Decide only on a settled tunnel whose certificate is known. While it starts, reasserts
        // after a network change, or before the first status reply after the app launches, the
        // proxy keeps running: stopping it there would drop every open browser connection.
        switch state {
        case .off, .failed: break
        case .on where status != nil: break
        default: return
        }
        let https = settings.https
        let wanted = state == .on && https.enabled && https.trustedCA != nil
            && https.trustedCA == status?.certificateFingerprint
        guard wanted != proxyWanted else { return }
        proxyWanted = wanted
        Task {
            do {
                let manager = try await browserProxyManager(create: wanted)
                guard let manager else { return }
                if wanted {
                    if [.disconnected, .invalid].contains(manager.connection.status) {
                        browserProxyError = nil
                        try manager.connection.startVPNTunnel()
                    }
                } else {
                    manager.connection.stopVPNTunnel()
                }
            } catch {
                browserProxyError = error.localizedDescription
                lastError = "Browser filtering could not start: \(error.localizedDescription)"
            }
        }
    }

    /// The browser proxy changed state. When it ends while it should run (macOS refused to launch
    /// it, or it stopped on its own), show the reason instead of a silent "Off".
    private func browserProxyChanged(_ connection: NEVPNConnection) {
        let previous = browserProxy
        browserProxy = connection.status
        switch connection.status {
        case .connected:
            browserProxyError = nil
        case .disconnected, .invalid:
            guard proxyWanted == true, previous != .disconnected, previous != .invalid else { return }
            Self.disconnectReason(of: connection) { [weak self] reason in
                guard let self, self.proxyWanted == true, self.browserProxy != .connected else { return }
                let message = reason?.message ?? "macOS stopped it without giving a reason"
                self.browserProxyError = message
                self.lastError = "Browser filtering could not start: \(message)"
                self.lastErrorNeedsSettings = reason?.needsSettings ?? false
            }
        default:
            break
        }
    }

    /// Why a connection last ended, as macOS recorded it.
    struct DisconnectReason {
        var message: String
        /// The fix is in System Settings › VPN & Filters, not in the app.
        var needsSettings: Bool
    }

    /// The error macOS recorded for the last time `connection` ended, nil after a normal stop.
    private static func disconnectReason(
        of connection: NEVPNConnection, _ completion: @escaping @MainActor (DisconnectReason?) -> Void
    ) {
        connection.fetchLastDisconnectError { error in
            let reason = error.map { error -> DisconnectReason in
                let nsError = error as NSError
                let settingsCodes: [NEVPNConnectionError] = [
                    .pluginFailed, .pluginDisabled, .configurationFailed, .configurationNotFound,
                ]
                let needsSettings = nsError.domain == NEVPNConnectionErrorDomain
                    && settingsCodes.contains { $0.rawValue == nsError.code }
                return DisconnectReason(message: nsError.localizedDescription, needsSettings: needsSettings)
            }
            Task { @MainActor in completion(reason) }
        }
    }

    /// Opens System Settings › VPN, where the user can switch the Open
    /// AdBlock configurations on, or remove a broken one so the app recreates it.
    static func openVPNSettings() {
        let panes = [
            "x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension",
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
        ]
        for pane in panes {
            if let url = URL(string: pane), NSWorkspace.shared.open(url) { return }
        }
    }

    private func browserProxyManager(create: Bool) async throws -> NETransparentProxyManager? {
        if let proxyManager { return proxyManager }
        let existing = try await NETransparentProxyManager.loadAllFromPreferences().first
        guard let manager = existing ?? (create ? NETransparentProxyManager() : nil) else { return nil }
        // Save the configuration once per launch, also when it exists: macOS records the code
        // signature of the app that saved it and refuses to launch the provider for a differently
        // signed build ("Signature check failed"), e.g. after moving from Apple Development to
        // Developer ID. The packet tunnel's configuration is re-saved on every apply already.
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = AppGroup.tunnelBundleIdentifier
        configuration.serverAddress = "Open AdBlock browser filtering"
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "Open AdBlock browser filtering"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        proxyManager = manager
        proxyObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.browserProxyChanged(manager.connection) }
        }
        browserProxy = manager.connection.status
        return manager
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.send(.status)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    private func send(_ command: TunnelCommand, settings: Settings? = nil) async {
        guard let session = manager?.connection as? NETunnelProviderSession,
            session.status == .connected,
            let request = try? JSONEncoder().encode(TunnelRequest(command: command, settings: settings))
        else { return }
        let reply: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(request) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(returning: nil)
            }
        }
        // The reply carries up to 500 log entries: decode it off the main thread, and publish only
        // a change, since every published status redraws each view that observes the tunnel.
        let decoded = await Task.detached(priority: .userInitiated) {
            reply.flatMap { try? JSONDecoder().decode(TunnelStatus.self, from: $0) }
        }.value
        if let decoded {
            if decoded != status { status = decoded }
            syncBrowserProxy()
        }
    }
}
