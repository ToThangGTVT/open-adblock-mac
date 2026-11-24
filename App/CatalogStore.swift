import Foundation

/// Fetches the AdGuard filter catalogs (the same API calls as the Android app) and caches them
/// for four days, the registry's own expiry. Catalogs are never bundled: AdGuard Home's registry
/// is GPL-3.0 and every list keeps its own license.
@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var entries: [CatalogSource: [CatalogEntry]] = [:]
    @Published private(set) var loading: Set<CatalogSource> = []
    @Published private(set) var errors: [CatalogSource: String] = [:]

    private static let maximumAge: TimeInterval = 4 * 24 * 60 * 60
    private static let sizeLimit = 2 * 1024 * 1024

    func load(_ source: CatalogSource, force: Bool = false) async {
        guard !loading.contains(source) else { return }
        loading.insert(source)
        defer { loading.remove(source) }
        let cache = AppGroup.container.appendingPathComponent("catalog-\(source.rawValue).json")
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate.map { Date().timeIntervalSince($0) } ?? .infinity
        do {
            let data: Data
            if !force, age < Self.maximumAge, let cached = try? Data(contentsOf: cache) {
                data = cached
            } else {
                do {
                    data = try await fetch(source.url)
                    try? data.write(to: cache, options: .atomic)
                } catch {
                    // Offline: an old catalog beats none.
                    guard let cached = try? Data(contentsOf: cache) else { throw error }
                    data = cached
                }
            }
            entries[source] = try FilterCatalog.parse(data, source: source)
            errors[source] = nil
        } catch {
            errors[source] = error.localizedDescription
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= Self.sizeLimit else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }
}
