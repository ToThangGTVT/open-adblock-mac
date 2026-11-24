import Foundation

/// Files the app and the packet tunnel share through their App Group container.
enum AppGroup {
    /// `$(TeamIdentifierPrefix)io.github.tothanggtvt.openadblock.mac`, injected into both
    /// Info.plists from `OAB_APP_GROUP` in Config/Base.xcconfig.
    static let identifier: String =
        Bundle.main.object(forInfoDictionaryKey: "OABAppGroup") as? String ?? ""

    static let container: URL = {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier)
        {
            return url
        }
        // Unsigned development builds have no group container; keep them working locally.
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenAdBlock", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    static var settingsURL: URL { container.appendingPathComponent("settings.json") }
    static var statisticsURL: URL { container.appendingPathComponent("statistics.json") }
    static var listsDirectory: URL {
        let url = container.appendingPathComponent("lists", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func listURL(_ id: String) -> URL { listsDirectory.appendingPathComponent("\(id).txt") }

    /// Bundle identifier of the packet tunnel extension.
    static let tunnelBundleIdentifier =
        (Bundle.main.bundleIdentifier ?? "io.github.tothanggtvt.openadblock.mac")
        .replacingOccurrences(of: ".tunnel", with: "") + ".tunnel"
}
