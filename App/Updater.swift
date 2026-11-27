import AppKit
import Combine
import Sparkle

/// In-app updates from GitHub Releases through Sparkle. The feed is the `appcast.xml` attached to
/// the latest (non pre-release) release; CI signs every update archive with the EdDSA key whose
/// public half is `SUPublicEDKey` in Config/App-Info.plist, and Sparkle
/// also requires the new app to carry the same Developer ID signature as the running one.
@MainActor
final class Updater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    /// False in builds without a public key (local development): Sparkle refuses updates there.
    let isConfigured: Bool
    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
    private var observation: AnyCancellable?

    override init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !key.trimmingCharacters(in: .whitespaces).isEmpty
        super.init()
        guard isConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func checkForUpdates() {
        // The app may have no Dock icon: bring it forward so Sparkle's window is not hidden.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// A menu bar app is rarely in front; let Sparkle show scheduled updates without stealing
    /// focus, and bring the app forward when it does show one.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}
