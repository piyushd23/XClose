import ApplicationServices
import Foundation

/// Watches an app that XClose hid while it quits, and reports the first sign that
/// the app needs the user: a new window or sheet (save or confirmation prompts),
/// or the app unhiding itself. Lives on the main run loop until invalidated.
final class AttentionWatch {
    private let observer: AXObserver
    private let application: AXUIElement
    private let handler: () -> Void
    private var isValid = true

    private static let notifications = [
        kAXWindowCreatedNotification,
        kAXSheetCreatedNotification,
        kAXApplicationShownNotification,
    ] as [String]

    /// Returns nil if the app can't be observed. Callers must then not hide it,
    /// because a hidden save prompt would go unnoticed.
    init?(pid: pid_t, handler: @escaping () -> Void) {
        var created: AXObserver?
        guard AXObserverCreate(pid, attentionCallback, &created) == .success, let created else { return nil }
        observer = created
        application = AXUIElementCreateApplication(pid)
        self.handler = handler

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        for name in Self.notifications where AXObserverAddNotification(observer, application, name as CFString, refcon) == .success {
            registered += 1
        }
        // Window and sheet creation are the ones that matter for prompts.
        guard registered >= 2 else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        for name in Self.notifications {
            AXObserverRemoveNotification(observer, application, name as CFString)
        }
    }

    fileprivate func fire() {
        guard isValid else { return }
        handler()
    }

    deinit {
        invalidate()
    }
}

private func attentionCallback(observer: AXObserver, element: AXUIElement, notification: CFString,
                               refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<AttentionWatch>.fromOpaque(refcon).takeUnretainedValue().fire()
}
