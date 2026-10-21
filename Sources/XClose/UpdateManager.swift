import AppKit
import Combine
import Sparkle

/// Sparkle auto-updates. Updates are EdDSA-signed and verified against
/// `SUPublicEDKey` before anything is installed. The only network traffic is the
/// appcast fetch (once a day if enabled) and the update download itself; Sparkle's
/// optional system profiling is not enabled.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    /// Version of an update found by a scheduled check, shown in the menu instead
    /// of interrupting the user with a window (XClose is a menu-bar app).
    @Published private(set) var pendingUpdateVersion: String?
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    /// Updates are only possible from a bundle that declares a feed and key.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary
        return info?["SUFeedURL"] is String && info?["SUPublicEDKey"] is String
    }

    func start() {
        guard Self.isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        activate()
        controller?.checkForUpdates(nil)
    }

    private func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension UpdateManager: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Only let Sparkle show its window right away if it would not interrupt
        // the user (for example just after launch); otherwise XClose shows a
        // menu item and the user opens the update when convenient.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                activate()
            } else {
                pendingUpdateVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { pendingUpdateVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { pendingUpdateVersion = nil }
    }
}
