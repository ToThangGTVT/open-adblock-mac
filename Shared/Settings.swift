import Foundation

/// Encrypted DNS upstreams the engine resolves through. Plain "system" DNS is not offered on
/// macOS: while the tunnel is up the system resolver is the tunnel itself.
enum DNSPreset: String, Codable, CaseIterable, Identifiable {
    case cloudflare, google, adguard, quad9, cloudflarePlain, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudflare: "Cloudflare (DNS-over-HTTPS)"
        case .google: "Google (DNS-over-HTTPS)"
        case .adguard: "AdGuard (DNS-over-HTTPS)"
        case .quad9: "Quad9 (DNS-over-HTTPS)"
        case .cloudflarePlain: "Cloudflare (plain DNS)"
        case .custom: "Custom"
        }
    }

    var upstream: Upstream? {
        switch self {
        case .cloudflare: Upstream(protocol: .https, ip: "1.1.1.1", serverName: "cloudflare-dns.com")
        case .google: Upstream(protocol: .https, ip: "8.8.8.8", serverName: "dns.google")
        case .adguard: Upstream(protocol: .https, ip: "94.140.14.140", serverName: "unfiltered.adguard-dns.com")
        case .quad9: Upstream(protocol: .https, ip: "9.9.9.9", serverName: "dns.quad9.net")
        case .cloudflarePlain: Upstream(protocol: .udp, ip: "1.1.1.1", serverName: "")
        case .custom: nil
        }
    }
}

struct Upstream: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case udp, tcp, tls, https, quic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .udp: "UDP"
            case .tcp: "TCP"
            case .tls: "DNS-over-TLS"
            case .https: "DNS-over-HTTPS"
            case .quic: "DNS-over-QUIC"
            }
        }
    }
    var `protocol`: Kind
    var ip: String
    var serverName: String
    var path = "/dns-query"
}

struct FilterListSetting: Codable, Equatable, Identifiable {
    var id: String
    var enabled: Bool
}

/// Everything the user configures. The app keeps it in its own storage and hands it to the tunnel
/// in the VPN configuration (on start) and in `apply` messages (while running); the tunnel keeps
/// the copy with the newest `revision`.
struct Settings: Codable, Equatable {
    var revision = Date(timeIntervalSince1970: 0)
    var dns: DNSPreset = .cloudflare
    var customUpstream = Upstream(protocol: .https, ip: "1.1.1.1", serverName: "cloudflare-dns.com")
    /// "zero" answers 0.0.0.0/::, "nxdomain" says the name does not exist.
    var blockMode = "zero"
    var ipv6 = true
    var logging = true
    var dpi = false
    var lists: [FilterListSetting] = FilterCatalog.all.map {
        FilterListSetting(id: $0.id, enabled: $0.enabledByDefault)
    }
    var customRules = ""

    var upstream: Upstream { dns.upstream ?? customUpstream }

    /// `configureDns` JSON, see open-adblock-core/docs/API.md.
    var dnsJSON: String {
        let value: [String: Any] = [
            "protocol": upstream.protocol.rawValue,
            "ip": upstream.ip,
            "serverName": upstream.serverName,
            "path": upstream.path,
            "blockMode": blockMode,
            "logging": logging,
        ]
        return Self.json(value)
    }

    /// `configurePolicy` JSON. Per-app policy does not exist on macOS (packets carry no owner).
    var policyJSON: String {
        Self.json(["ipv6": ipv6, "dpi": ["enabled": dpi]])
    }

    private static func json(_ value: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: AppGroup.settingsURL), let settings = decode(data)
        else { return Settings() }
        return settings
    }

    static func decode(_ data: Data) -> Settings? {
        guard var settings = try? JSONDecoder().decode(Settings.self, from: data) else { return nil }
        // Lists added to the catalog after the settings were saved.
        for list in FilterCatalog.all where !settings.lists.contains(where: { $0.id == list.id }) {
            settings.lists.append(FilterListSetting(id: list.id, enabled: list.enabledByDefault))
        }
        return settings
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    func save() throws {
        try encoded().write(to: AppGroup.settingsURL, options: .atomic)
    }

    var enabledLists: [String] { lists.filter(\.enabled).map(\.id) }
}

extension Settings {
    init(from decoder: Decoder) throws {
        // Every field optional so settings saved by an older version keep loading.
        let defaults = Settings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = (try? c.decode(Date.self, forKey: .revision)) ?? defaults.revision
        dns = (try? c.decode(DNSPreset.self, forKey: .dns)) ?? defaults.dns
        customUpstream = (try? c.decode(Upstream.self, forKey: .customUpstream)) ?? defaults.customUpstream
        blockMode = (try? c.decode(String.self, forKey: .blockMode)) ?? defaults.blockMode
        ipv6 = (try? c.decode(Bool.self, forKey: .ipv6)) ?? defaults.ipv6
        logging = (try? c.decode(Bool.self, forKey: .logging)) ?? defaults.logging
        dpi = (try? c.decode(Bool.self, forKey: .dpi)) ?? defaults.dpi
        lists = (try? c.decode([FilterListSetting].self, forKey: .lists)) ?? defaults.lists
        customRules = (try? c.decode(String.self, forKey: .customRules)) ?? defaults.customRules
    }
}
