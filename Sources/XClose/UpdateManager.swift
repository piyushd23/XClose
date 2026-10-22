import AppKit
import Combine
import Sparkle
import UserNotifications

/// Sparkle auto-updates. Updates are EdDSA-signed and verified against
/// `SUPublicEDKey` before anything is installed. The only network traffic is the
/// appcast fetch (once a day if enabled) and the update download itself; Sparkle's
/// optional system profiling is not enabled.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    /// Version of an update found by a scheduled check. Shown as a dot on the
    /// menu-bar icon, a menu item and a one-time notification, instead of
    /// interrupting the user with a window (XClose is a menu-bar app).
    @Published private(set) var pendingUpdateVersion: String?
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []
    private static let notifiedVersionKey = "notifiedUpdateVersion"

    /// Updates are only possible from a bundle that declares a feed and key.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary
        return info?["SUFeedURL"] is String && info?["SUPublicEDKey"] is String
    }

    func start() {
        guard Self.isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        UNUserNotificationCenter.current().delegate = self
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

    /// Posts "XClose <version> is available" once per version. Notification
    /// permission is requested here, the first time an update is actually found,
    /// so new users never see an unexplained permission prompt.
    private func notifyOnce(about version: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.notifiedVersionKey) != version else { return }
        defaults.set(version, forKey: Self.notifiedVersionKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = "XClose \(version) is available"
            content.body = "Click to see what's new and install the update."
            center.add(UNNotificationRequest(identifier: "xclose-update-\(version)", content: content, trigger: nil))
        }
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
                notifyOnce(about: version)
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

extension UpdateManager: UNUserNotificationCenterDelegate {
    /// Show the banner even if XClose happens to be the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    /// Clicking the notification opens Sparkle's update window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.checkForUpdates() }
            completionHandler()
        }
    }
}
