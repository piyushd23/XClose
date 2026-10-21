import AppKit
import XCloseCore

struct DiagnosticEvent: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case state = "State"
        case intercepted = "Intercepted"
        case passed = "Passed"
        case releasedOutside = "Released outside"
        case quitRequested = "Quit requested"
        case quitConfirmed = "Quit confirmed"
        case quitNotConfirmed = "Quit not confirmed"
        case quitDuplicate = "Duplicate ignored"
        case quitSkipped = "Quit skipped"
        case quitRequestFailed = "Quit request failed"
        case quitShownAgain = "Shown again"
        case tap = "Event tap"
        case permission = "Permission"
    }

    let id = UUID()
    let date: Date
    let kind: Kind
    /// App names, reasons and timings only: never window titles, document
    /// contents, keystrokes or URLs.
    let detail: String
}

/// Bounded, in-memory only. Nothing is written to disk or sent anywhere.
@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var events = BoundedLog<DiagnosticEvent>(capacity: 200)
    @Published private(set) var passCounts: [PassReason: Int] = [:]
    @Published private(set) var interceptedCount = 0
    @Published private(set) var quitRequestedCount = 0
    @Published private(set) var quitConfirmedCount = 0
    @Published private(set) var quitNotConfirmedCount = 0
    @Published private(set) var tapTimeoutCount = 0
    @Published private(set) var lastDetectionMilliseconds: Double?
    @Published private(set) var slowestDetectionMilliseconds: Double = 0

    func record(_ kind: DiagnosticEvent.Kind, _ detail: String) {
        events.append(DiagnosticEvent(date: Date(), kind: kind, detail: detail))
        switch kind {
        case .quitRequested: quitRequestedCount += 1
        case .quitConfirmed: quitConfirmedCount += 1
        case .quitNotConfirmed: quitNotConfirmedCount += 1
        default: break
        }
    }

    func record(_ evaluation: ClickEvaluation) {
        let name = evaluation.appName ?? evaluation.pid.map { "pid \($0)" } ?? "—"
        let timing = String(format: "%.1f ms", evaluation.elapsedMilliseconds)
        switch evaluation.result {
        case .success:
            interceptedCount += 1
            noteTiming(evaluation.elapsedMilliseconds)
            record(.intercepted, "\(name) red × (\(timing))")
        case .failure(let reason):
            passCounts[reason, default: 0] += 1
            // Only log clicks that reached the Accessibility stage; ordinary
            // content clicks are counted, not logged.
            if reason.reachedAccessibility {
                noteTiming(evaluation.elapsedMilliseconds)
                record(.passed, "\(name): \(reason.summary) (\(timing))")
            }
        }
    }

    func recordTapDisabled(byTimeout: Bool) {
        if byTimeout { tapTimeoutCount += 1 }
        record(.tap, byTimeout ? "Disabled by timeout; re-enabled" : "Disabled by user input; re-enabled")
    }

    func clear() {
        events.removeAll()
        passCounts = [:]
        interceptedCount = 0
        quitRequestedCount = 0
        quitConfirmedCount = 0
        quitNotConfirmedCount = 0
        tapTimeoutCount = 0
        lastDetectionMilliseconds = nil
        slowestDetectionMilliseconds = 0
    }

    private func noteTiming(_ ms: Double) {
        lastDetectionMilliseconds = ms
        slowestDetectionMilliseconds = max(slowestDetectionMilliseconds, ms)
    }

    func report(state: OperationalState, tapStatus: TapStatus, trusted: Bool) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines = [
            "XClose \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "State: \(state.title) | Tap: \(tapStatus) | Accessibility: \(trusted ? "granted" : "not granted")",
            "Intercepted: \(interceptedCount) | Quit requested: \(quitRequestedCount) | confirmed: \(quitConfirmedCount) | not confirmed: \(quitNotConfirmedCount)",
            "Tap timeouts: \(tapTimeoutCount) | slowest detection: \(String(format: "%.1f", slowestDetectionMilliseconds)) ms",
            "Pass-through counts:",
        ]
        for (reason, count) in passCounts.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(reason.rawValue): \(count)")
        }
        lines.append("Recent events:")
        let formatter = ISO8601DateFormatter()
        for event in events.elements.suffix(60) {
            lines.append("  \(formatter.string(from: event.date)) [\(event.kind.rawValue)] \(event.detail)")
        }
        return lines.joined(separator: "\n")
    }
}
