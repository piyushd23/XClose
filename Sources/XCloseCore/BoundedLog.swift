import Foundation

/// Fixed-capacity log that drops the oldest entries first.
public struct BoundedLog<Element>: Sendable where Element: Sendable {
    public let capacity: Int
    public private(set) var elements: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        elements.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        if elements.count == capacity { elements.removeFirst() }
        elements.append(element)
    }

    public mutating func removeAll() {
        elements.removeAll(keepingCapacity: true)
    }

    public var count: Int { elements.count }
}

/// Short-lived per-process penalty after an Accessibility timeout, so a hung app
/// does not stall every click in its title bar.
public struct PenaltyBox: Sendable {
    public var duration: TimeInterval
    private var until: [Int32: TimeInterval] = [:]

    public init(duration: TimeInterval = 5) {
        self.duration = duration
    }

    public mutating func penalize(_ pid: Int32, now: TimeInterval) {
        until[pid] = now + duration
        if until.count > 64 { until = until.filter { $0.value > now } }
    }

    public func isPenalized(_ pid: Int32, now: TimeInterval) -> Bool {
        (until[pid] ?? 0) > now
    }

    public mutating func removeAll() {
        until.removeAll()
    }
}
