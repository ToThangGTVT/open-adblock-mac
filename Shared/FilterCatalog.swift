import Foundation

/// Where filter catalogs come from: the same two AdGuard catalogs as the Android app.
enum CatalogSource: String, CaseIterable, Identifiable, Codable {
    /// AdGuard Home's blocklist registry: DNS-level lists for every app.
    case dns
    /// The AdGuard browser extension's filters in uBlock Origin syntax: used on decrypted HTTPS.
    case browser

    var id: String { rawValue }
    var browser: Bool { self == .browser }

    var url: URL {
        switch self {
        case .dns: URL(string: "https://adguardteam.github.io/HostlistsRegistry/assets/filters.json")!
        case .browser: URL(string: "https://filters.adtidy.org/extension/ublock/filters.json")!
        }
    }

    var title: String {
        switch self {
        case .dns: "DNS block lists"
        case .browser: "Browser filters"
        }
    }

    /// Lists the AdGuard catalog repackages; the original sources are fresher (as on Android).
    static let mirrored: [Int: URL] = [
        101: URL(string: "https://easylist.to/easylist/easylist.txt")!,
        118: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
        214: URL(string: "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn.txt")!,
    ]
}

/// One list offered by a catalog.
struct CatalogEntry: Identifiable, Hashable {
    var id: String
    var name: String
    var summary: String
    var group: String
    var groupOrder: Int
    var order: Int
    var url: URL
    var recommended: Bool
    var languages: [String]
    var browser: Bool

    var setting: FilterListSetting {
        FilterListSetting(id: id, name: name, url: url, browser: browser, enabled: true)
    }
}

enum FilterCatalog {
    /// First-run subscriptions: AdGuard DNS filter for all apps, EasyList + EasyPrivacy for
    /// browsers (used once browser filtering is turned on).
    static let defaults: [FilterListSetting] = [
        FilterListSetting(
            id: "dns:1", name: "AdGuard DNS filter",
            url: URL(string: "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt")!,
            browser: false, enabled: true),
        FilterListSetting(
            id: "browser:101", name: "EasyList", url: CatalogSource.mirrored[101]!, browser: true,
            enabled: true),
        FilterListSetting(
            id: "browser:118", name: "EasyPrivacy", url: CatalogSource.mirrored[118]!, browser: true,
            enabled: true),
    ]

    /// Parses an AdGuard `filters.json` (both catalogs share the format).
    static func parse(_ data: Data, source: CatalogSource) throws -> [CatalogEntry] {
        struct Document: Decodable {
            struct Filter: Decodable {
                var filterId: Int
                var name: String
                var description: String?
                var groupId: Int
                var displayNumber: Int?
                var downloadUrl: String?
                var deprecated: Bool?
                var tags: [Int]?
                var languages: [String]?
            }
            struct Group: Decodable {
                var groupId: Int
                var groupName: String
                var displayNumber: Int?
            }
            struct Tag: Decodable {
                var tagId: Int
                var keyword: String
            }
            var filters: [Filter]
            var groups: [Group]?
            var tags: [Tag]?
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        let recommended = document.tags?.first { $0.keyword == "recommended" }?.tagId
        let groups = Dictionary(
            (document.groups ?? []).map { ($0.groupId, $0) }, uniquingKeysWith: { first, _ in first })
        return document.filters.compactMap { filter in
            guard filter.deprecated != true else { return nil }
            let mirrored = source.browser ? CatalogSource.mirrored[filter.filterId] : nil
            guard let url = mirrored ?? filter.downloadUrl.flatMap(URL.init(string:)),
                url.scheme == "https"
            else { return nil }
            let group = groups[filter.groupId]
            return CatalogEntry(
                id: "\(source.rawValue):\(filter.filterId)", name: String(filter.name.prefix(200)),
                summary: filter.description ?? "", group: group?.groupName ?? "Other",
                groupOrder: group?.displayNumber ?? filter.groupId, order: filter.displayNumber ?? 0,
                url: url, recommended: recommended.map { filter.tags?.contains($0) == true } ?? false,
                languages: filter.languages ?? [], browser: source.browser)
        }
        .sorted { ($0.groupOrder, $0.order, $0.name) < ($1.groupOrder, $1.order, $1.name) }
    }
}

/// Browsers the transparent proxy can hand to the core.
struct KnownBrowser: Identifiable, Hashable {
    var id: String
    var name: String

    static let all: [KnownBrowser] = [
        KnownBrowser(id: "com.apple.Safari", name: "Safari"),
        KnownBrowser(id: "com.google.Chrome", name: "Google Chrome"),
        KnownBrowser(id: "com.microsoft.edgemac", name: "Microsoft Edge"),
        KnownBrowser(id: "com.brave.Browser", name: "Brave"),
        KnownBrowser(id: "org.mozilla.firefox", name: "Firefox"),
        KnownBrowser(id: "company.thebrowser.Browser", name: "Arc"),
        KnownBrowser(id: "com.operasoftware.Opera", name: "Opera"),
        KnownBrowser(id: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        KnownBrowser(id: "com.coccoc.Coccoc", name: "Cốc Cốc"),
    ]

    /// The selected browser a flow belongs to: its own id or one of its helpers'
    /// (`com.google.Chrome.helper`, `com.apple.WebKit.Networking` for Safari).
    static func owner(of signingIdentifier: String, among selected: [String]) -> String? {
        if signingIdentifier.hasPrefix("com.apple.WebKit"), selected.contains("com.apple.Safari") {
            return "com.apple.Safari"
        }
        return selected.first { signingIdentifier == $0 || signingIdentifier.hasPrefix($0 + ".") }
    }
}
