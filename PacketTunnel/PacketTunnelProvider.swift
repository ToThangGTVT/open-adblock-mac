import Darwin
import Network
import NetworkExtension
import OpenAdBlockCore
import os

private let logger = Logger(subsystem: "io.github.tothanggtvt.openadblock.mac", category: "tunnel")

/// Runs the Open AdBlock core in packet mode: the system hands app packets to `packetFlow`, the
/// core answers DNS itself, filters and relays the rest over its own (non-tunnelled) sockets.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    /// Must match the virtual addresses the core recognises (crates/engine/src/tun/mod.rs).
    private enum Address {
        static let ipv4 = "172.19.0.1"
        static let dns4 = "172.19.0.2"
        static let ipv6 = "fdfe:dcba:9876::1"
        static let dns6 = "fdfe:dcba:9876::2"
        static let mtu = 9000
    }

    private let engine = NativeEngine.shared
    private let events = EventStore()
    private let protector = InterfaceProtector()
    private var settings = Settings.load()
    private var report = RuleReport(loaded: 0, ignored: 0, errors: [])
    private var startedAt: Date?
    private var reading = false
    private let pathMonitor = NWPathMonitor()
    private var lastPath: Network.NWPath?

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        guard let engine else {
            throw NEVPNError(.configurationInvalid)
        }
        settings = Settings.load()
        apply(settings, to: engine)
        try await setTunnelNetworkSettings(networkSettings())

        engine.setEventListener(events)
        let sink = FlowSink(flow: packetFlow)
        guard engine.startPackets(protector: protector, dns: settings.upstream.ip, sink: sink) else {
            throw NEVPNError(.connectionFailed)
        }
        startedAt = Date()
        reading = true
        readPackets()
        watchNetwork()
        logger.info("Tunnel started, core \(engine.version, privacy: .public), \(self.report.loaded) rules")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        reading = false
        pathMonitor.cancel()
        engine?.stop()
        engine?.setEventListener(nil)
        startedAt = nil
        logger.info("Tunnel stopped: \(reason.rawValue)")
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let request = try? JSONDecoder().decode(TunnelRequest.self, from: messageData) else {
            return nil
        }
        switch request.command {
        case .reload:
            settings = Settings.load()
            if let engine { apply(settings, to: engine) }
            // IPv6 routes and DNS servers depend on settings too.
            try? await setTunnelNetworkSettings(networkSettings())
        case .clearLog:
            events.clear()
        case .status:
            break
        }
        engine?.flushEvents()
        return try? JSONEncoder().encode(status())
    }

    // MARK: Engine

    private func apply(_ settings: Settings, to engine: NativeEngine) {
        if !engine.configureDNS(json: settings.dnsJSON) {
            logger.error("DNS configuration rejected")
        }
        engine.configurePolicy(json: settings.policyJSON)
        var lists = ""
        for list in settings.lists where list.enabled {
            if let text = try? String(contentsOf: AppGroup.listURL(list.id), encoding: .utf8) {
                lists += text
                lists += "\n"
            }
        }
        report = engine.replaceRules(dns: lists, browser: "", custom: settings.customRules, apply: true)
    }

    private func status() -> TunnelStatus {
        let counters = engine?.counters ?? TrafficCounters()
        let today = events.snapshot()
        return TunnelStatus(
            engineVersion: engine?.version ?? "unavailable",
            rulesLoaded: report.loaded, ruleErrors: report.errors.count,
            todayTotal: today.total, todayBlocked: today.blocked, topBlocked: today.top,
            recent: today.recent, packetsIn: counters.packetsIn, packetsOut: counters.packetsOut,
            tcpBytesUp: counters.tcpBytesUp, tcpBytesDown: counters.tcpBytesDown,
            connections: counters.tcpOpened + counters.udpOpened, startedAt: startedAt)
    }

    // MARK: Packets

    private func networkSettings() -> NEPacketTunnelNetworkSettings {
        let network = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: [Address.ipv4], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Keep the local network reachable directly (printers, AirDrop, router admin).
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "224.0.0.0", subnetMask: "240.0.0.0"),
        ]
        network.ipv4Settings = ipv4
        var servers = [Address.dns4]
        if settings.ipv6 {
            let ipv6 = NEIPv6Settings(addresses: [Address.ipv6], networkPrefixLengths: [126])
            ipv6.includedRoutes = [NEIPv6Route.default()]
            ipv6.excludedRoutes = [
                NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10),
                NEIPv6Route(destinationAddress: "ff00::", networkPrefixLength: 8),
            ]
            network.ipv6Settings = ipv6
            servers.append(Address.dns6)
        }
        let dns = NEDNSSettings(servers: servers)
        dns.matchDomains = [""]
        network.dnsSettings = dns
        network.mtu = NSNumber(value: Address.mtu)
        return network
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, self.reading, let engine = self.engine else { return }
            for packet in packets { engine.send(packet: packet) }
            self.readPackets()
        }
    }

    private func watchNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.protector.update(path)
            defer { self.lastPath = path }
            // Drop upstream sockets bound to the old interface when the network really changes.
            guard let last = self.lastPath, path.status == .satisfied,
                last.availableInterfaces.first?.name != path.availableInterfaces.first?.name
            else { return }
            self.engine?.updateNetwork(dns: self.settings.upstream.ip)
        }
        pathMonitor.start(queue: DispatchQueue(label: "openadblock.path"))
    }
}

/// Writes the core's packets back to the system, tagged with their IP version.
private final class FlowSink: PacketSink {
    private let flow: NEPacketTunnelFlow
    init(flow: NEPacketTunnelFlow) { self.flow = flow }

    func onPacket(_ packet: Data) {
        guard let first = packet.first else { return }
        let family = first >> 4 == 6 ? AF_INET6 : AF_INET
        flow.writePackets([packet], withProtocols: [NSNumber(value: family)])
    }
}

/// The extension's own sockets already bypass the tunnel. Binding them to the physical
/// interface as well keeps them off the tunnel even if routing changes underneath.
private final class InterfaceProtector: SocketProtector, @unchecked Sendable {
    private let lock = NSLock()
    private var index: UInt32 = 0

    func update(_ path: Network.NWPath) {
        let physical = path.availableInterfaces.first { $0.type != .other && $0.type != .loopback }
        lock.lock()
        index = physical.map { UInt32($0.index) } ?? 0
        lock.unlock()
    }

    func protect(socket: Int64) -> Bool {
        lock.lock()
        var index = self.index
        lock.unlock()
        guard index != 0 else { return true }
        let fd = Int32(truncatingIfNeeded: socket)
        let size = socklen_t(MemoryLayout<UInt32>.size)
        // The engine opens IPv4 and IPv6 sockets; exactly one of the two options applies.
        if setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, size) != 0 {
            _ = setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, size)
        }
        return true
    }
}
