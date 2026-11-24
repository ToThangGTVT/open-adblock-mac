import Foundation

/// State the packet tunnel publishes for the browser proxy. Both providers live in the same
/// system extension process.
final class SharedState: @unchecked Sendable {
    static let shared = SharedState()

    private let lock = NSLock()
    private var browsers: [String] = []
    private var active = false
    private var flows = 0
    private var seen: Set<String> = []

    /// Called by the packet tunnel whenever it applies settings or stops.
    func update(browsers: [String], decrypting: Bool) {
        lock.withLock {
            self.browsers = browsers
            active = decrypting
        }
    }

    /// The selected browser a flow belongs to, while browser filtering is active.
    func browser(for signingIdentifier: String) -> String? {
        lock.withLock {
            guard active else { return nil }
            return KnownBrowser.owner(of: signingIdentifier, among: browsers)
        }
    }

    func countFlow() { lock.withLock { flows += 1 } }
    var browserFlows: Int { lock.withLock { flows } }

    /// True the first time an app id shows up (for diagnostics in the log).
    func firstSight(_ signingIdentifier: String) -> Bool {
        lock.withLock { seen.insert(signingIdentifier).inserted }
    }
}
