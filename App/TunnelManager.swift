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
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var poller: Task<Void, Never>?

    init() {
        Task { await load() }
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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool, settings: Settings) {
        Task {
            do {
                if enabled { try await start(settings) } else { manager?.connection.stopVPNTunnel() }
            } catch {
                lastError = error.localizedDescription
                refreshState()
            }
        }
    }

    /// Hands changed settings to the running tunnel, and to the VPN configuration so the next
    /// start (also one the system triggers) uses them.
    func apply(_ settings: Settings) {
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
        switch manager.connection.status {
        case .connected: state = .on
        case .connecting, .reasserting: state = .connecting
        case .disconnecting: state = .disconnecting
        case .invalid, .disconnected: state = .off
        @unknown default: state = .off
        }
        if state == .on { startPolling() } else if state == .off { stopPolling() }
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
        if let reply, let status = try? JSONDecoder().decode(TunnelStatus.self, from: reply) {
            self.status = status
        }
    }
}
