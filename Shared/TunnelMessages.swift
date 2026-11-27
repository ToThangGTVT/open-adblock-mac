import Foundation

/// App → tunnel requests over `NETunnelProviderSession.sendProviderMessage`. Every request is
/// answered with a `TunnelStatus`.
enum TunnelCommand: String, Codable {
    case status
    /// Store and apply `TunnelRequest.settings` (downloads newly enabled lists).
    case apply
    /// Download every enabled list again.
    case updateLists
    /// Forget the query log and today's numbers.
    case clearLog
}

struct TunnelRequest: Codable {
    var command: TunnelCommand
    var settings: Settings?
}

/// One DNS answer or blocked connection.
struct LogEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    var domain: String
    var blocked: Bool
    var rule: String?
    var cached: Bool
    var kind: String
    /// Path of an inspected HTTPS request; nil for DNS answers and other connections.
    var path: String?
    /// The app that made the request; nil when unknown (DNS goes through the system resolver).
    var app: AppInfo?

    /// `https://domain/path` for inspected requests, otherwise the domain alone.
    var url: String {
        guard let path else { return domain }
        return "https://\(domain)\(path)"
    }
}

/// An app as the log shows it.
struct AppInfo: Codable, Hashable {
    var name: String
    var bundleID: String?
    /// The `.app` bundle, or the executable of a command-line tool or daemon.
    var path: String?
}

struct DomainCount: Codable, Hashable, Identifiable {
    var domain: String
    var count: Int
    var id: String { domain }
}

/// A block list as the tunnel holds it.
struct ListStatus: Codable, Hashable, Identifiable {
    var id: String
    var updated: Date?
    var entries: Int
    var downloading: Bool
    var error: String?
}

struct TunnelStatus: Codable, Equatable {
    var engineVersion: String
    var rulesLoaded: Int
    var ruleErrors: Int
    var todayTotal: Int
    var todayBlocked: Int
    var topBlocked: [DomainCount]
    var recent: [LogEntry]
    var lists: [ListStatus]
    /// DER of the local root CA, once browser filtering created it.
    var certificate: Data?
    var certificateFingerprint: String?
    /// Browser connections handed to the core since the extension started.
    var browserFlows: Int
    var packetsIn: Int64
    var packetsOut: Int64
    var tcpBytesUp: Int64
    var tcpBytesDown: Int64
    var connections: Int64
    var startedAt: Date?
}
