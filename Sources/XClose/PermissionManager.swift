import AppKit
import ApplicationServices

/// Accessibility is the only permission XClose needs: it is required both for an
/// event tap that can block mouse events and for reading other apps' window
/// controls. Input Monitoring (keyboard listening), Screen Recording, Automation
/// and Full Disk Access are not used.
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()

    private var observers: [NSObjectProtocol] = []

    func startMonitoring() {
        // Posted by the system whenever the Accessibility trust database changes.
        // The trust value can lag the notification slightly, so check twice.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted { isAccessibilityTrusted = trusted }
    }

    /// Only called from an explicit "Grant Access…" click, never automatically.
    /// Each call registers XClose in the Accessibility list at its *current*
    /// location, which matters if the app was moved after a previous request.
    func requestAccess() {
        refresh()
        guard !isAccessibilityTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Accessibility grants are tied to the app's location and signature, so
    /// granting access to a copy outside Applications tends to break later.
    var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// For adding XClose by hand with the + button or by dragging it into the list.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
