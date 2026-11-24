import Foundation

/// DNS-level block lists the app can download. The same lists as the Android app's defaults.
struct FilterList: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let url: URL
    let enabledByDefault: Bool
}

enum FilterCatalog {
    static let all: [FilterList] = [
        FilterList(
            id: "adguard-dns", name: "AdGuard DNS filter",
            summary: "Ads, trackers and analytics, built for DNS blocking.",
            url: URL(string: "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt")!,
            enabledByDefault: true),
        FilterList(
            id: "stevenblack", name: "StevenBlack unified hosts",
            summary: "Adware and malware hosts merged from several sources.",
            url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!,
            enabledByDefault: false),
        FilterList(
            id: "abpvn", name: "ABPVN",
            summary: "Vietnamese ad domains.",
            url: URL(string: "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn.txt")!,
            enabledByDefault: false),
    ]

    static func list(_ id: String) -> FilterList? { all.first { $0.id == id } }
}
