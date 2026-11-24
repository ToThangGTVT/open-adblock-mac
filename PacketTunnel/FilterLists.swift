import Foundation

/// Downloads and stores the block lists inside the tunnel's own (root) container, and remembers
/// when each was fetched. Lists older than a day are refreshed when the tunnel starts.
final class FilterLists: @unchecked Sendable {
    private struct Entry: Codable {
        var updated: Date
        var entries: Int
    }

    private static let maximumAge: TimeInterval = 24 * 60 * 60
    private let lock = NSLock()
    private var index: [String: Entry]
    private var downloading: Set<String> = []
    private var errors: [String: String] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    init() {
        index =
            (try? Data(contentsOf: AppGroup.listsIndexURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// Text of the enabled lists that are on disk, joined for the DNS matcher.
    func text(for ids: [String]) -> String {
        ids.compactMap { try? String(contentsOf: AppGroup.listURL($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    /// Ids among `ids` that were never downloaded or are older than a day (or all with `force`).
    func stale(_ ids: [String], force: Bool = false) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return ids.filter { id in
            guard !downloading.contains(id) else { return false }
            guard !force, let entry = index[id] else { return true }
            return Date().timeIntervalSince(entry.updated) > Self.maximumAge
        }
    }

    /// Downloads `ids` one by one; returns true when at least one list changed on disk.
    func download(_ ids: [String]) async -> Bool {
        var changed = false
        for id in ids {
            guard let list = FilterCatalog.list(id), begin(id) else { continue }
            do {
                let (data, response) = try await session.data(from: list.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                    throw URLError(.badServerResponse)
                }
                try data.write(to: AppGroup.listURL(id), options: .atomic)
                finish(id, entry: Entry(updated: Date(), entries: Self.count(data)), error: nil)
                changed = true
            } catch {
                finish(id, entry: nil, error: error.localizedDescription)
            }
        }
        return changed
    }

    func status() -> [ListStatus] {
        lock.lock()
        defer { lock.unlock() }
        return FilterCatalog.all.map { list in
            ListStatus(
                id: list.id, updated: index[list.id]?.updated, entries: index[list.id]?.entries ?? 0,
                downloading: downloading.contains(list.id), error: errors[list.id])
        }
    }

    private func begin(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return downloading.insert(id).inserted
    }

    private func finish(_ id: String, entry: Entry?, error: String?) {
        lock.lock()
        defer { lock.unlock() }
        downloading.remove(id)
        errors[id] = error
        if let entry {
            index[id] = entry
            if let data = try? JSONEncoder().encode(index) {
                try? data.write(to: AppGroup.listsIndexURL, options: .atomic)
            }
        }
    }

    private static func count(_ data: Data) -> Int {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).count { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("#")
        }
    }
}
