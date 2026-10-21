import AppKit
import XCloseCore

/// Turns a validated red × release into a normal quit request and follows it up.
///
/// Uses `NSRunningApplication.terminate()`, which asks the app to quit exactly
/// like Quit / ⌘Q: the app runs its own save prompts and may delay or refuse.
/// XClose never force-quits, never signals, never dismisses dialogs, and never
/// retries on its own.
@MainActor
final class QuitCoordinator {
    private var tracker = QuitRequestTracker()
    private let diagnostics: DiagnosticsStore
    private var expiryScheduled = false

    /// Re-checks policy at request time, in case it changed since the press.
    var currentEligibility: ((AppDescriptor) -> AppEligibility)?
    /// Whether to hide the app the moment its quit is requested.
    var hidesWhileQuitting: () -> Bool = { false }

    /// Apps hidden while quitting. If one is still running after this long, it is
    /// shown again so nothing can be left hidden (slow quit, or a prompt that the
    /// watch missed).
    static let revealDelay: TimeInterval = 3
    private var hiddenApps: [Int32: AttentionWatch] = [:]

    init(diagnostics: DiagnosticsStore) {
        self.diagnostics = diagnostics
    }

    enum Result: Equatable {
        case requested
        case suppressedDuplicate
        case skipped(String)
    }

    @discardableResult
    func requestQuit(for click: ArmedClick) -> Result {
        let now = ProcessInfo.processInfo.systemUptime
        guard let app = NSRunningApplication(processIdentifier: pid_t(click.pid)), !app.isTerminated else {
            diagnostics.record(.quitSkipped, "\(click.appName): process already gone")
            return .skipped("process gone")
        }
        // Guard against pid reuse between press and release.
        let descriptor = ApplicationLifecycleMonitor.descriptor(for: app)
        guard descriptor.key == click.appKey else {
            diagnostics.record(.quitSkipped, "\(click.appName): process identity changed")
            return .skipped("identity changed")
        }
        if let eligibility = currentEligibility?(descriptor), !eligibility.isEligible {
            diagnostics.record(.quitSkipped, "\(descriptor.name): no longer eligible")
            return .skipped("ineligible")
        }
        guard tracker.decide(pid: click.pid, now: now) == .submit else {
            diagnostics.record(.quitDuplicate, descriptor.name)
            return .suppressedDuplicate
        }

        let request = QuitRequest(pid: click.pid, appKey: click.appKey, appName: descriptor.name, requestedAt: now)
        // Hide first so the windows disappear immediately, as a normal red × does;
        // the app's own shutdown (often a second or more) then happens out of sight.
        let hid = hidesWhileQuitting() && hideWhileQuitting(app)
        if app.terminate() {
            tracker.recordSubmitted(request)
            let pressToRequest = (now - click.armedAt) * 1000
            diagnostics.record(.quitRequested, "\(descriptor.name) (\(Int(pressToRequest)) ms after press\(hid ? ", hidden" : ""))")
            scheduleExpiry()
            return .requested
        } else {
            reveal(pid: click.pid, reason: nil)
            tracker.recordSubmissionFailed(pid: click.pid)
            diagnostics.record(.quitRequestFailed, "\(descriptor.name): macOS did not deliver the quit request")
            return .skipped("terminate() returned false")
        }
    }

    func applicationTerminated(pid: Int32) {
        hiddenApps.removeValue(forKey: pid)?.invalidate()
        guard case .terminated(let request, let after)? = tracker.applicationTerminated(pid: pid, now: ProcessInfo.processInfo.systemUptime) else {
            return
        }
        diagnostics.record(.quitConfirmed, "\(request.appName) exited after \(String(format: "%.1f", after)) s")
    }

    func reset() {
        tracker.removeAll()
        for pid in Array(hiddenApps.keys) { reveal(pid: pid, reason: nil) }
    }

    /// Hides `app` only if XClose can watch it for prompts; otherwise leaves it visible.
    private func hideWhileQuitting(_ app: NSRunningApplication) -> Bool {
        guard !app.isHidden else { return false }
        let pid = Int32(app.processIdentifier)
        guard let watch = AttentionWatch(pid: pid_t(pid), handler: { [weak self] in
            MainActor.assumeIsolated { self?.reveal(pid: pid, reason: "it needs your attention") }
        }) else { return false }
        hiddenApps[pid]?.invalidate()
        hiddenApps[pid] = watch
        app.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealDelay) { [weak self] in
            MainActor.assumeIsolated { self?.reveal(pid: pid, reason: "still running after \(Int(Self.revealDelay)) s") }
        }
        return true
    }

    /// Shows a hidden app again and brings it forward so any prompt is visible.
    private func reveal(pid: Int32, reason: String?) {
        guard let watch = hiddenApps.removeValue(forKey: pid) else { return }
        watch.invalidate()
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)), !app.isTerminated else { return }
        app.unhide()
        app.activate()
        if let reason { diagnostics.record(.quitShownAgain, "\(app.localizedName ?? "App") shown again: \(reason)") }
    }

    private func scheduleExpiry() {
        guard !expiryScheduled, let next = tracker.nextExpiry else { return }
        expiryScheduled = true
        let delay = max(0.1, next - ProcessInfo.processInfo.systemUptime + 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.expiryScheduled = false
                for case .notConfirmed(let request) in self.tracker.expire(now: ProcessInfo.processInfo.systemUptime) {
                    self.diagnostics.record(.quitNotConfirmed, "\(request.appName) still running (cancelled, delayed or refused)")
                }
                self.scheduleExpiry()
            }
        }
    }
}
