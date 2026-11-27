import Foundation
import OpenAdBlockCore

/// Receives the engine's batched events and keeps what the app shows: a bounded query log,
/// today's totals and the most blocked domains. Totals survive tunnel restarts on disk.
final class EventStore: EngineEventListener, @unchecked Sendable {
    private struct Batch: Decodable {
        struct Event: Decodable {
            var timestamp: Double
            var domain: String
            var blocked: Bool
            var matchedRule: String?
            var cached: Bool
            var `protocol`: String
            var path: String?
            var uid: UInt32?
        }
        struct Total: Decodable {
            var timestamp: Double
            var total: Int
            var blocked: Int
        }
        var events: [Event]
        var totals: [Total]
    }

    private struct Persisted: Codable {
        var day: String
        var total: Int
        var blocked: Int
        var blockedDomains: [String: Int]
    }

    private static let logLimit = 1000
    private let lock = NSLock()
    private var log: [LogEntry] = []
    private var today: Persisted

    init() {
        let day = Self.day(Date())
        if let data = try? Data(contentsOf: AppGroup.statisticsURL),
            let saved = try? JSONDecoder().decode(Persisted.self, from: data), saved.day == day
        {
            today = saved
        } else {
            today = Persisted(day: day, total: 0, blocked: 0, blockedDomains: [:])
        }
    }

    func onEvents(_ json: String) {
        guard let batch = try? JSONDecoder().decode(Batch.self, from: Data(json.utf8)) else { return }
        lock.lock()
        defer { lock.unlock() }
        rollOverIfNeeded()
        for total in batch.totals where Self.day(Date(timeIntervalSince1970: total.timestamp / 1000)) == today.day {
            today.total += total.total
            today.blocked += total.blocked
        }
        for event in batch.events {
            log.append(
                LogEntry(
                    timestamp: Date(timeIntervalSince1970: event.timestamp / 1000), domain: event.domain,
                    blocked: event.blocked, rule: event.matchedRule, cached: event.cached,
                    kind: event.protocol, path: event.path,
                    app: event.uid.flatMap(AppDirectory.shared.info(for:))))
            if event.blocked { today.blockedDomains[event.domain, default: 0] += 1 }
        }
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        // Keep the domain table bounded on long-running days.
        if today.blockedDomains.count > 2000 {
            today.blockedDomains = Dictionary(
                uniqueKeysWithValues: today.blockedDomains.sorted { $0.value > $1.value }.prefix(1000)
                    .map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(today) {
            try? data.write(to: AppGroup.statisticsURL, options: .atomic)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        log.removeAll()
        today = Persisted(day: Self.day(Date()), total: 0, blocked: 0, blockedDomains: [:])
        try? FileManager.default.removeItem(at: AppGroup.statisticsURL)
    }

    func snapshot() -> (total: Int, blocked: Int, top: [DomainCount], recent: [LogEntry]) {
        lock.lock()
        defer { lock.unlock() }
        rollOverIfNeeded()
        let top = today.blockedDomains.sorted { $0.value > $1.value }.prefix(10)
            .map { DomainCount(domain: $0.key, count: $0.value) }
        return (today.total, today.blocked, top, Array(log.suffix(500).reversed()))
    }

    private func rollOverIfNeeded() {
        let day = Self.day(Date())
        if today.day != day { today = Persisted(day: day, total: 0, blocked: 0, blockedDomains: [:]) }
    }

    private static func day(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
