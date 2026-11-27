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
    private let lists = FilterLists()
    private let certificates = CertificateStore()
    private var settings = Settings.load()
    private var report = RuleReport(loaded: 0, ignored: 0, errors: [])
    private var startedAt: Date?
    private var reading = false
    private let pathMonitor = NWPathMonitor()
    private var lastPath: Network.NWPath?
    private var watchdog: EngineWatchdog?

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        guard let engine else {
            throw NEVPNError(.configurationInvalid)
        }
        settings = newestSettings()
        try? settings.save()
        apply(settings, to: engine)
        try await setTunnelNetworkSettings(networkSettings())

        engine.setEventListener(events)
        guard startEngine(engine) else {
            throw NEVPNError(.connectionFailed)
        }
        startedAt = Date()
        reading = true
        let watchdog = EngineWatchdog(
            engine: engine,
            restart: { [weak self] in
                guard let self, self.reading else { return false }
                engine.stop()
                return self.startEngine(engine)
            },
            giveUp: { [weak self] in
                self?.cancelTunnelWithError(NEVPNError(.connectionFailed))
            })
        self.watchdog = watchdog
        watchdog.start()
        readPackets()
        watchNetwork()
        refreshLists(force: false)
        logger.info("Tunnel started, core \(engine.version, privacy: .public), \(self.report.loaded) rules")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        reading = false
        watchdog?.stop()
        watchdog = nil
        pathMonitor.cancel()
        SharedState.shared.update(browsers: [], decrypting: false)
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
        case .apply:
            guard let new = request.settings else { break }
            let ipv6Changed = new.ipv6 != settings.ipv6
            settings = new
            try? settings.save()
            if let engine { apply(settings, to: engine) }
            // IPv6 routes and DNS servers depend on settings too.
            if ipv6Changed { try? await setTunnelNetworkSettings(networkSettings()) }
            refreshLists(force: false)
        case .updateLists:
            refreshLists(force: true)
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

        // Browser filtering: the CA exists once the user turned it on; decryption only runs for
        // the exact CA the app verified as trusted, so browsing never meets an unknown issuer.
        let authority = certificates.load(create: settings.https.enabled, engine: engine)
        if let authority {
            engine.setRootCA(
                signer: authority.signer, publicPoint: authority.publicPoint,
                certificate: authority.certificate)
        }
        let decrypting = settings.https.enabled && authority != nil
            && settings.https.trustedCA == authority?.fingerprint
        engine.configureHTTPS(json: settings.httpsJSON(ca: authority?.fingerprint))
        SharedState.shared.update(browsers: settings.https.browsers, decrypting: decrypting)

        report = engine.replaceRules(
            dns: lists.text(for: settings.enabledLists(browser: false)),
            browser: settings.https.enabled
                ? lists.text(for: settings.enabledLists(browser: true)) + "\n" + FilterLists.browserFixes
                : "",
            custom: settings.customRules, apply: true)
    }

    /// The VPN configuration carries the settings of the last start; the tunnel's own copy may be
    /// newer when the app applied changes while it was running.
    private func newestSettings() -> Settings {
        let stored = Settings.load()
        let configured = ((protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?[AppGroup.settingsKey] as? Data)
            .flatMap(Settings.decode)
        guard let configured else { return stored }
        return configured.revision >= stored.revision ? configured : stored
    }

    /// Downloads stale lists (browser lists and scriptlets only with browser filtering on) in the
    /// background, then recompiles the rules with them.
    private func refreshLists(force: Bool) {
        let wanted = settings.enabledLists(browser: false)
            + (settings.https.enabled ? settings.enabledLists(browser: true) : [])
        let stale = lists.stale(wanted, force: force)
        let resources = settings.https.enabled
        guard !stale.isEmpty || resources else { return }
        Task { [weak self] in
            guard let self, let engine = self.engine else { return }
            if resources { await self.lists.installResources(into: engine) }
            guard !stale.isEmpty, await self.lists.download(stale) else { return }
            self.apply(self.settings, to: engine)
            logger.info("Lists updated, \(self.report.loaded) rules")
        }
    }

    private func status() -> TunnelStatus {
        let counters = engine?.counters ?? TrafficCounters()
        let today = events.snapshot()
        return TunnelStatus(
            engineVersion: engine?.version ?? "unavailable",
            rulesLoaded: report.loaded, ruleErrors: report.errors.count,
            todayTotal: today.total, todayBlocked: today.blocked, topBlocked: today.top,
            recent: today.recent, lists: lists.status(for: settings.lists),
            certificate: certificates.authority?.certificate,
            certificateFingerprint: certificates.authority?.fingerprint,
            browserFlows: SharedState.shared.browserFlows, packetsIn: counters.packetsIn, packetsOut: counters.packetsOut,
            tcpBytesUp: counters.tcpBytesUp, tcpBytesDown: counters.tcpBytesDown,
            connections: counters.tcpOpened + counters.udpOpened, startedAt: startedAt)
    }

    // MARK: Packets

    private func networkSettings() -> NEPacketTunnelNetworkSettings {
        let network = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: [Address.ipv4], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [
            NEIPv4Route.default(),
            // The tunnel's own /30 (DNS at .2) sits inside 172.16/12, excluded below: keep it in.
            NEIPv4Route(destinationAddress: "172.19.0.0", subnetMask: "255.255.255.252"),
        ]
        // The local network is never filtered: every private, link-local, multicast and
        // broadcast destination goes straight to the physical interface (printers, NAS, router
        // admin, AirDrop/AirPlay, Docker and VM networks in 172.16/12, LAN discovery).
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "224.0.0.0", subnetMask: "240.0.0.0"),
            NEIPv4Route(destinationAddress: "255.255.255.255", subnetMask: "255.255.255.255"),
        ]
        network.ipv4Settings = ipv4
        var servers = [Address.dns4]
        if settings.ipv6 {
            let ipv6 = NEIPv6Settings(addresses: [Address.ipv6], networkPrefixLengths: [126])
            ipv6.includedRoutes = [
                NEIPv6Route.default(),
                // The tunnel's own /126 is a unique local address, excluded below with fc00::/7.
                NEIPv6Route(destinationAddress: "fdfe:dcba:9876::", networkPrefixLength: 126),
            ]
            ipv6.excludedRoutes = [
                NEIPv6Route(destinationAddress: "fc00::", networkPrefixLength: 7),
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

    /// Starts the core's packet mode, writing its packets back to `packetFlow`. The rules,
    /// policy and event listener live in the core across restarts.
    private func startEngine(_ engine: NativeEngine) -> Bool {
        engine.startPackets(
            protector: protector, dns: settings.upstream.ip, sink: FlowSink(flow: packetFlow))
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, self.reading, let engine = self.engine else { return }
            var accepted = 0
            for packet in packets where engine.send(packet: packet) { accepted += 1 }
            self.watchdog?.record(accepted: accepted, refused: packets.count - accepted)
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

    func connectionOwner(
        protocol: UInt8, source: String, sourcePort: UInt16, destination: String,
        destinationPort: UInt16
    ) -> Int64? {
        AppDirectory.shared.owner(protocol: `protocol`, sourcePort: sourcePort, destinationPort: destinationPort)
    }
}
