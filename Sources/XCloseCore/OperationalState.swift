import Foundation

public enum TapStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case failedToStart
    /// Disabled by the system repeatedly; stopped until retried.
    case unstable
}

public enum DegradedReason: String, Equatable, Sendable {
    case eventTapUnavailable
    case eventTapUnstable

    public var summary: String {
        switch self {
        case .eventTapUnavailable: return "The click interceptor could not start."
        case .eventTapUnstable: return "The click interceptor was repeatedly disabled by macOS and has been paused."
        }
    }
}

public enum OperationalState: Equatable, Sendable {
    case paused
    case permissionRequired
    case starting
    case operational
    case degraded(DegradedReason)

    public static func derive(isEnabled: Bool, hasAccessibility: Bool, tap: TapStatus) -> OperationalState {
        guard isEnabled else { return .paused }
        guard hasAccessibility else { return .permissionRequired }
        switch tap {
        case .running: return .operational
        case .stopped, .starting: return .starting
        case .failedToStart: return .degraded(.eventTapUnavailable)
        case .unstable: return .degraded(.eventTapUnstable)
        }
    }

    /// Only this state may alter clicks. Everything else passes events through.
    public var interceptsClicks: Bool { self == .operational }

    public var title: String {
        switch self {
        case .paused: return "Paused"
        case .permissionRequired: return "Accessibility access required"
        case .starting: return "Starting…"
        case .operational: return "Active"
        case .degraded: return "Not working"
        }
    }
}

public enum TapAction: Equatable, Sendable {
    case none
    case start
    case stop
}

public enum TapPlanner {
    /// What to do with the event tap so it matches the desired state. Failed or
    /// unstable taps are not restarted automatically here; the caller retries on
    /// explicit user action, permission grant, or wake.
    public static func action(isEnabled: Bool, hasAccessibility: Bool, tap: TapStatus) -> TapAction {
        if isEnabled && hasAccessibility {
            return tap == .stopped ? .start : .none
        }
        return tap == .stopped ? .none : .stop
    }
}

/// Detects an event tap that macOS keeps disabling (callback too slow, or
/// something else interfering) so XClose can stop instead of flapping.
public struct TapHealthMonitor: Sendable {
    public var window: TimeInterval
    public var threshold: Int
    public private(set) var recentDisables: [TimeInterval] = []

    public init(window: TimeInterval = 60, threshold: Int = 3) {
        self.window = window
        self.threshold = threshold
    }

    /// Returns true when the tap should be considered unstable.
    public mutating func recordTimeout(now: TimeInterval) -> Bool {
        recentDisables.append(now)
        recentDisables.removeAll { now - $0 > window }
        return recentDisables.count >= threshold
    }

    public mutating func reset() {
        recentDisables.removeAll()
    }
}
