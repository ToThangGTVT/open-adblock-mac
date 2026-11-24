import Foundation

/// App → tunnel requests over `NETunnelProviderSession.sendProviderMessage`.
enum TunnelCommand: String, Codable {
    /// Returns a `TunnelStatus`.
    case status
    /// Re-read settings and lists from the App Group container and apply them.
    case reload
    /// Forget the query log and today's numbers.
    case clearLog
}

struct TunnelRequest: Codable {
    var command: TunnelCommand
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
}

struct DomainCount: Codable, Hashable, Identifiable {
    var domain: String
    var count: Int
    var id: String { domain }
}

struct TunnelStatus: Codable {
    var engineVersion: String
    var rulesLoaded: Int
    var ruleErrors: Int
    var todayTotal: Int
    var todayBlocked: Int
    var topBlocked: [DomainCount]
    var recent: [LogEntry]
    var packetsIn: Int64
    var packetsOut: Int64
    var tcpBytesUp: Int64
    var tcpBytesDown: Int64
    var connections: Int64
    var startedAt: Date?
}
