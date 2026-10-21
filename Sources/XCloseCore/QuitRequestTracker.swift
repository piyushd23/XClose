import Foundation

public struct QuitRequest: Equatable, Sendable {
    public var pid: Int32
    public var appKey: AppKey?
    public var appName: String
    public var requestedAt: TimeInterval

    public init(pid: Int32, appKey: AppKey?, appName: String, requestedAt: TimeInterval) {
        self.pid = pid
        self.appKey = appKey
        self.appName = appName
        self.requestedAt = requestedAt
    }
}

public enum QuitSubmitDecision: Equatable, Sendable {
    case submit
    case suppressDuplicate
}

public enum QuitOutcome: Equatable, Sendable {
    /// The process actually exited (observed via workspace notification).
    case terminated(QuitRequest, after: TimeInterval)
    /// The app is still running after the confirmation window: the user cancelled,
    /// the app is still saving, or it refused. XClose never retries on its own.
    case notConfirmed(QuitRequest)
}

/// Tracks quit requests per process. A request is distinct from termination:
/// `terminate()` returning true only means the request was delivered.
public struct QuitRequestTracker: Sendable {
    /// Repeat clicks on red × within this window are swallowed without a new request.
    public var duplicateWindow: TimeInterval
    /// After this long without termination the request is reported as not confirmed.
    public var confirmationTimeout: TimeInterval
    public private(set) var pending: [Int32: QuitRequest] = [:]

    public init(duplicateWindow: TimeInterval = 2, confirmationTimeout: TimeInterval = 30) {
        self.duplicateWindow = duplicateWindow
        self.confirmationTimeout = confirmationTimeout
    }

    public func decide(pid: Int32, now: TimeInterval) -> QuitSubmitDecision {
        if let existing = pending[pid], now - existing.requestedAt < duplicateWindow {
            return .suppressDuplicate
        }
        // Past the duplicate window a click is a fresh, user-initiated request
        // (for example after cancelling a save dialog), so it is allowed.
        return .submit
    }

    public func isAwaitingTermination(pid: Int32) -> Bool {
        pending[pid] != nil
    }

    public mutating func recordSubmitted(_ request: QuitRequest) {
        pending[request.pid] = request
    }

    public mutating func recordSubmissionFailed(pid: Int32) {
        pending[pid] = nil
    }

    public mutating func applicationTerminated(pid: Int32, now: TimeInterval) -> QuitOutcome? {
        guard let request = pending.removeValue(forKey: pid) else { return nil }
        return .terminated(request, after: max(0, now - request.requestedAt))
    }

    public mutating func expire(now: TimeInterval) -> [QuitOutcome] {
        let expired = pending.values.filter { now - $0.requestedAt >= confirmationTimeout }
        for request in expired { pending[request.pid] = nil }
        return expired.sorted { $0.requestedAt < $1.requestedAt }.map { .notConfirmed($0) }
    }

    /// Earliest time at which `expire(now:)` would report something.
    public var nextExpiry: TimeInterval? {
        pending.values.map { $0.requestedAt + confirmationTimeout }.min()
    }

    public mutating func removeAll() {
        pending.removeAll()
    }
}
