import AppKit
import XCloseCore

/// Keeps a pid → descriptor snapshot of running apps from NSWorkspace
/// notifications (no polling) and relays system events that require the event
/// tap to be re-checked.
@MainActor
final class ApplicationLifecycleMonitor: ObservableObject {
    @Published private(set) var apps: [Int32: AppDescriptor] = [:]

    var onTerminate: ((Int32) -> Void)?
    var onSystemResume: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        apps = Dictionary(NSWorkspace.shared.runningApplications.map { (Int32($0.processIdentifier), Self.descriptor(for: $0)) },
                          uniquingKeysWith: { _, latest in latest })

        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            })
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in self?.update(from: note) }
        // Apps can switch activation policy at runtime; re-read on activation.
        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] note in self?.update(from: note) }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = Int32(app.processIdentifier)
            self?.apps[pid] = nil
            self?.onTerminate?(pid)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(name) { [weak self] _ in self?.onSystemResume?() }
        }
    }

    /// Called when the tap meets a pid that has no entry yet (launch notification
    /// not delivered yet, or a pid reused after a restart).
    func refresh(pid: Int32) {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)), !app.isTerminated {
            apps[pid] = Self.descriptor(for: app)
        } else {
            apps[pid] = nil
        }
    }

    private func update(from note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let descriptor = Self.descriptor(for: app)
        if apps[descriptor.pid] != descriptor { apps[descriptor.pid] = descriptor }
    }

    static func descriptor(for app: NSRunningApplication) -> AppDescriptor {
        AppDescriptor(
            pid: Int32(app.processIdentifier),
            bundleID: app.bundleIdentifier,
            bundlePath: (app.bundleURL ?? app.executableURL)?.standardizedFileURL.path,
            name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "pid \(app.processIdentifier)",
            isRegularApp: app.activationPolicy == .regular
        )
    }
}
