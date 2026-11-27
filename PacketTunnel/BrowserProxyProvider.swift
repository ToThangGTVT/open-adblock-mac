import Foundation
import Network
import NetworkExtension
import OpenAdBlockCore
import os

private let logger = Logger(subsystem: "io.github.tothanggtvt.openadblock.mac", category: "browser-proxy")

/// Hands browser HTTPS connections to the core's app proxy, where they are decrypted with the
/// local root CA and filtered with the browser lists. Every other app's traffic is declined and
/// flows normally (DNS filtering still covers it through the packet tunnel).
///
/// Unlike the packet tunnel, a transparent proxy learns each flow's app
/// (`sourceAppSigningIdentifier`), which is what limits decryption to browsers.
final class BrowserProxyProvider: NETransparentProxyProvider {
    override func startProxy(options: [String: Any]? = nil) async throws {
        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        // Only port 443 is ever considered: TCP for TLS, UDP so browsers' QUIC can be refused
        // (they fall back to TCP, which can be filtered).
        settings.includedNetworkRules = [
            Self.rule(.TCP, "0.0.0.0"), Self.rule(.TCP, "::"),
            Self.rule(.UDP, "0.0.0.0"), Self.rule(.UDP, "::"),
        ]
        try await setTunnelNetworkSettings(settings)
        logger.info("Browser proxy started")
    }

    override func stopProxy(with reason: NEProviderStopReason) async {
        logger.info("Browser proxy stopped: \(reason.rawValue)")
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        let app = flow.metaData.sourceAppSigningIdentifier
        if SharedState.shared.firstSight(app) {
            logger.info("First flow from \(app, privacy: .public)")
        }
        guard let browser = SharedState.shared.browser(for: app) else { return false }

        if let udp = flow as? NEAppProxyUDPFlow {
            // QUIC would bypass decryption: refuse it so the browser retries over TCP.
            let refused = NSError(domain: NEAppProxyErrorDomain, code: NEAppProxyFlowError.refused.rawValue)
            udp.closeReadWithError(refused)
            udp.closeWriteWithError(refused)
            return true
        }
        guard let tcp = flow as? NEAppProxyTCPFlow,
            let remote = tcp.remoteEndpoint as? NWHostEndpoint,
            let port = UInt16(remote.port),
            let proxy = NativeEngine.shared?.openAppProxy()
        else { return false }
        SharedState.shared.countFlow()
        FlowBridge(
            flow: tcp, proxyPort: proxy.port,
            header: proxy.header(host: remote.hostname, port: port, app: browser)
        ).start()
        return true
    }

    private static func rule(_ proto: NENetworkRule.`Protocol`, _ any: String) -> NENetworkRule {
        NENetworkRule(
            destinationNetwork: NWHostEndpoint(hostname: any, port: "443"), prefix: 0, protocol: proto)
    }
}

/// Copies one app flow to the core's loopback app proxy and back, preserving half-close.
private final class FlowBridge: @unchecked Sendable {
    private let flow: NEAppProxyTCPFlow
    private let connection: NWConnection
    private let header: Data
    private let queue = DispatchQueue(label: "openadblock.flow")
    private var finished = false
    private var upstreamDone = false
    private var downstreamDone = false

    init(flow: NEAppProxyTCPFlow, proxyPort: UInt16, header: Data) {
        self.flow = flow
        self.header = header
        connection = NWConnection(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: proxyPort)!, using: .tcp)
    }

    /// The bridge keeps itself alive through the handlers it gives `connection` and `flow`;
    /// `finish` cancels both sides so every pending callback returns and the cycle ends.
    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                connection.stateUpdateHandler = { [self] state in
                    switch state {
                    case .failed, .waiting: finish()
                    default: break
                    }
                }
                connection.send(content: header, completion: .contentProcessed { [self] error in
                    error == nil ? openFlow() : finish()
                })
            // A refused loopback connect (core proxy gone, e.g. the tunnel stopped) parks a TCP
            // NWConnection in .waiting and retries forever, holding the browser flow open.
            case .failed, .waiting, .cancelled:
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func openFlow() {
        flow.open(withLocalEndpoint: nil) { [self] error in
            queue.async { [self] in
                guard error == nil else { return finish() }
                appToCore()
                coreToApp()
            }
        }
    }

    private func appToCore() {
        flow.readData { [self] data, error in
            queue.async { [self] in
                if let data, !data.isEmpty, error == nil {
                    connection.send(content: data, completion: .contentProcessed { [self] error in
                        error == nil ? appToCore() : finish()
                    })
                } else {
                    // The app finished sending: half-close toward the core.
                    connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                    completion: .contentProcessed { _ in })
                    upstreamDone = true
                    if downstreamDone || error != nil { finish() }
                }
            }
        }
    }

    private func coreToApp() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [self] data, _, complete, error in
            if let data, !data.isEmpty {
                flow.write(data) { [self] writeError in
                    queue.async { [self] in
                        guard writeError == nil else { return finish() }
                        complete ? closeDownstream() : coreToApp()
                    }
                }
            } else if complete || error != nil {
                closeDownstream()
            } else {
                coreToApp()
            }
        }
    }

    private func closeDownstream() {
        flow.closeWriteWithError(nil)
        downstreamDone = true
        if upstreamDone { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        // Drop the handler (it captures self) instead of relying on Network framework to release it.
        connection.stateUpdateHandler = nil
        connection.cancel()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
    }
}
