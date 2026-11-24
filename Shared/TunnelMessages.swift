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

struct TunnelStatus: Codable {
    var engineVersion: String
    var rulesLoaded: Int
    var ruleErrors: Int
    var todayTotal: Int
    var todayBlocked: Int
    var topBlocked: [DomainCount]
    var recent: [LogEntry]
    var lists: [ListStatus]
    var packetsIn: Int64
    var packetsOut: Int64
    var tcpBytesUp: Int64
    var tcpBytesDown: Int64
    var connections: Int64
    var startedAt: Date?
}
