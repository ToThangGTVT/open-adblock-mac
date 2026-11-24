import AppKit
import Foundation
import SystemExtensions

/// Installs (or updates) the packet tunnel system extension. macOS asks the user once to allow
/// it in System Settings › General › Login Items & Extensions; the app must run from
/// /Applications for the request to be accepted.
@MainActor
final class ExtensionInstaller: NSObject, ObservableObject {
    enum State: Equatable {
        case unknown, activating, needsApproval, ready
        case failed(String)
    }

    @Published private(set) var state: State = .unknown

    func activate() {
        guard state != .activating, state != .ready else { return }
        state = .activating
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: AppGroup.tunnelBundleIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func openApprovalSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension ExtensionInstaller: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // Always install the copy bundled with this app, so app and tunnel stay in step.
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsApproval }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            self.state = result == .completed ? .ready : .needsApproval
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message: String
        switch (error as NSError).code {
        case OSSystemExtensionError.unsupportedParentBundleLocation.rawValue:
            message = "Move Open AdBlock to the Applications folder, then open it again."
        default:
            message = error.localizedDescription
        }
        Task { @MainActor in self.state = .failed(message) }
    }
}
