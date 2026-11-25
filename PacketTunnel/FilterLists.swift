import Foundation
import OpenAdBlockCore

/// Downloads and stores the subscribed block lists and the AdGuard scriptlet resources inside the
/// extension's own (root) container. Anything older than a day is refreshed.
final class FilterLists: @unchecked Sendable {
    private struct Entry: Codable {
        var updated: Date
        var entries: Int
    }

    /// AdGuard Scriptlets resources for `##+js(...)` and `$redirect` rules (same as Android).
    /// Major version pinned: same JSON formats, fixes arrive without an app update.
    private static let resources: [(name: String, url: URL)] = [
        ("scriptlets", URL(string: "https://cdn.jsdelivr.net/npm/@adguard/scriptlets@2/dist/scriptlets.corelibs.json")!),
        ("redirects", URL(string: "https://cdn.jsdelivr.net/npm/@adguard/scriptlets@2/dist/redirects.json")!),
    ]
    private static let maximumAge: TimeInterval = 24 * 60 * 60
    private static let sizeLimit = 32 * 1024 * 1024
    private let lock = NSLock()
    private var index: [String: Entry]
    private var downloading: Set<String> = []
    private var errors: [String: String] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    init() {
        index =
            (try? Data(contentsOf: AppGroup.listsIndexURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// Rules added to the browser lists whatever the subscriptions. Desktop YouTube loads the
    /// next video's player response with `fetch`; the lists only cover it on m.youtube.com (AdGuard
    /// Base) and with uBlock-only scriptlets, so www.youtube.com kept its ads after the first video.
    static let browserFixes = """
        youtube.com,youtube-nocookie.com,youtubekids.com##+js(json-prune, playerResponse.adPlacements playerResponse.playerAds playerResponse.adSlots adPlacements playerAds adSlots)
        """

    /// Text of the given lists that are on disk, joined for the engine.
    func text(for lists: [FilterListSetting]) -> String {
        lists.compactMap { try? String(contentsOf: file($0.id), encoding: .utf8) }
            .joined(separator: "\n")
    }

    /// Lists never downloaded or older than a day (all of them with `force`).
    func stale(_ lists: [FilterListSetting], force: Bool = false) -> [FilterListSetting] {
        lock.lock()
        defer { lock.unlock() }
        return lists.filter { list in
            guard !downloading.contains(list.id) else { return false }
            guard !force, let entry = index[list.id] else { return true }
            return Date().timeIntervalSince(entry.updated) > Self.maximumAge
        }
    }

    /// Downloads `lists` one by one; true when at least one changed on disk.
    func download(_ lists: [FilterListSetting]) async -> Bool {
        var changed = false
        for list in lists {
            if await fetch(id: list.id, from: list.url, count: true) { changed = true }
        }
        return changed
    }

    /// Installs the scriptlet resources into the engine, downloading them when stale.
    func installResources(into engine: NativeEngine) async {
        let stale = lock.withLock {
            Self.resources.contains { resource in
                index[resource.name].map { Date().timeIntervalSince($0.updated) > Self.maximumAge } ?? true
            }
        }
        if stale {
            for resource in Self.resources {
                _ = await fetch(id: resource.name, from: resource.url, count: false)
            }
        }
        let text = Self.resources.map { (try? String(contentsOf: file($0.name), encoding: .utf8)) ?? "" }
        if text.contains(where: { !$0.isEmpty }) {
            _ = engine.setResources(scriptlets: text[0], redirects: text[1])
        }
    }

    func status(for lists: [FilterListSetting]) -> [ListStatus] {
        lock.lock()
        defer { lock.unlock() }
        return lists.map { list in
            ListStatus(
                id: list.id, updated: index[list.id]?.updated, entries: index[list.id]?.entries ?? 0,
                downloading: downloading.contains(list.id), error: errors[list.id])
        }
    }

    private func file(_ id: String) -> URL {
        // Ids are catalog keys ("dns:1") or URL hashes; keep file names plain.
        AppGroup.listURL(id.replacingOccurrences(of: ":", with: "-"))
    }

    private func fetch(id: String, from url: URL, count: Bool) async -> Bool {
        guard lock.withLock({ downloading.insert(id).inserted }) else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            guard data.count <= Self.sizeLimit else { throw URLError(.dataLengthExceedsMaximum) }
            try data.write(to: file(id), options: .atomic)
            finish(id, entry: Entry(updated: Date(), entries: count ? Self.count(data) : 0), error: nil)
            return true
        } catch {
            finish(id, entry: nil, error: error.localizedDescription)
            return false
        }
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
                && !trimmed.hasPrefix("[")
        }
    }
}
