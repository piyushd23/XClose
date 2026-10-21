import CoreGraphics
import Foundation

/// A validated red × press that has been swallowed and is waiting for release.
public struct ArmedClick: Equatable, Sendable {
    public var pid: Int32
    public var appKey: AppKey?
    public var appName: String
    public var buttonFrame: CGRect
    public var armedAt: TimeInterval

    public init(pid: Int32, appKey: AppKey?, appName: String, buttonFrame: CGRect, armedAt: TimeInterval) {
        self.pid = pid
        self.appKey = appKey
        self.appName = appName
        self.buttonFrame = buttonFrame
        self.armedAt = armedAt
    }
}

public enum EventDisposition: Equatable, Sendable {
    case pass
    case swallow
}

public enum MouseUpOutcome: Equatable, Sendable {
    case notTracked
    case cancelledDraggedAway(ArmedClick)
    case requestQuit(ArmedClick)
}

/// Sequences mouse-down / dragged / up for one button press.
///
/// Once a mouse-down is swallowed, the matching drags and the mouse-up are
/// swallowed too so the target app never sees half a click. The quit is only
/// requested on release inside the button, mirroring normal button semantics:
/// dragging away before release cancels. Exactly one of "original close" and
/// "quit request" can happen per press, because an armed press never reaches
/// the target app.
public struct ClickSequenceTracker: Sendable {
    public private(set) var armed: ArmedClick?
    public var releaseTolerance: CGFloat

    public init(releaseTolerance: CGFloat = 4) {
        self.releaseTolerance = releaseTolerance
    }

    /// `arm` is non-nil only for a validated red × press. Any previous armed press
    /// whose mouse-up was never seen is discarded.
    public mutating func mouseDown(arm: ArmedClick?) -> EventDisposition {
        armed = arm
        return arm == nil ? .pass : .swallow
    }

    public func mouseDragged() -> EventDisposition {
        armed == nil ? .pass : .swallow
    }

    public mutating func mouseUp(at point: CGPoint) -> (EventDisposition, MouseUpOutcome) {
        guard let click = armed else { return (.pass, .notTracked) }
        armed = nil
        let target = click.buttonFrame.insetBy(dx: -releaseTolerance, dy: -releaseTolerance)
        return (.swallow, target.contains(point) ? .requestQuit(click) : .cancelledDraggedAway(click))
    }

    public mutating func reset() {
        armed = nil
    }
}
