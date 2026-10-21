import CoreGraphics
import Foundation
import os
import XCloseCore

/// Owns the session-level CGEvent tap and the click sequencing.
///
/// The tap runs on a dedicated thread with its own run loop so a busy main thread
/// never delays system-wide mouse input. The callback does at most one window-list
/// query and a fixed number of time-capped Accessibility calls, and only for
/// left mouse-downs inside a title-bar area. Everything else is a dictionary
/// lookup or less. If anything is uncertain the event passes through unchanged.
final class MouseEventInterceptor {
    enum Notice {
        case evaluated(ClickEvaluation)
        case quitRequested(ArmedClick)
        case releasedOutside(ArmedClick)
        case tapDisabled(byTimeout: Bool)
        case unknownApplication(Int32)
        case accessibilityUnavailable
    }

    /// Value stored in `eventSourceUserData` by any event XClose might post. It
    /// does not post events today; the check guards against future recursion.
    static let syntheticMarker: Int64 = 0x58436C6F7365 // "XClose"

    /// Delivered on the main queue.
    var onNotice: ((Notice) -> Void)?

    private let configuration = OSAllocatedUnfairLock(initialState: InterceptorConfiguration())
    private let inspector: ClickInspector

    // Written before `start()` returns, read on main; the tap thread only reads.
    private var tap: CFMachPort?
    /// Drag events are only needed while a red × press is armed. Keeping them in a
    /// separate tap that is disabled the rest of the time takes XClose out of the
    /// path of every other drag (text selection, window moves) on the system.
    private var dragTap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var sources: [CFRunLoopSource] = []

    // Tap-thread-only state.
    private var tracker = ClickSequenceTracker()
    private var penalties = PenaltyBox()

    init(inspector: ClickInspector) {
        self.inspector = inspector
    }

    var isRunning: Bool { tap != nil }

    var isTapEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func updateConfiguration(_ update: (inout InterceptorConfiguration) -> Void) {
        configuration.withLock { update(&$0) }
    }

    /// Creates the tap on its own thread. Returns false if macOS refused it
    /// (normally: Accessibility access missing or not yet propagated).
    func start() -> Bool {
        if tap != nil { return true }
        let ready = DispatchSemaphore(value: 0)
        var created = false
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            self.tracker.reset()
            self.penalties.removeAll()
            let clickMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            let dragMask = 1 << CGEventType.leftMouseDragged.rawValue
            func makeTap(_ mask: Int) -> CFMachPort? {
                CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                  eventsOfInterest: CGEventMask(mask), callback: interceptorCallback,
                                  userInfo: Unmanaged.passUnretained(self).toOpaque())
            }
            guard let port = makeTap(clickMask), let dragPort = makeTap(dragMask) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            for machPort in [port, dragPort] {
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0)!
                CFRunLoopAddSource(loop, source, .commonModes)
                self.sources.append(source)
            }
            CGEvent.tapEnable(tap: port, enable: true)
            CGEvent.tapEnable(tap: dragPort, enable: false)
            self.tap = port
            self.dragTap = dragPort
            self.runLoop = loop
            created = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "XClose.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        if ready.wait(timeout: .now() + 2) == .timedOut { return false }
        return created
    }

    /// Removes the tap. Normal input is restored as soon as this returns.
    func stop() {
        guard let tap else { return }
        for port in [tap, dragTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop {
            for source in sources { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
        self.tap = nil
        self.dragTap = nil
        self.sources = []
        self.runLoop = nil
    }

    /// Re-enables a tap that macOS disabled (for example after sleep).
    func reenableIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Tap thread

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tracker.reset()
            setDragTracking(false)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            post(.tapDisabled(byTimeout: type == .tapDisabledByTimeout))
            return pass

        case .leftMouseDown:
            return handleMouseDown(event) == .swallow ? nil : pass

        case .leftMouseDragged:
            return tracker.mouseDragged() == .swallow ? nil : pass

        case .leftMouseUp:
            let (disposition, outcome) = tracker.mouseUp(at: event.location)
            setDragTracking(false)
            switch outcome {
            case .requestQuit(let click): post(.quitRequested(click))
            case .cancelledDraggedAway(let click): post(.releasedOutside(click))
            case .notTracked: break
            }
            return disposition == .swallow ? nil : pass

        default:
            return pass
        }
    }

    private func handleMouseDown(_ event: CGEvent) -> EventDisposition {
        let config = configuration.withLock { $0 }
        let now = ProcessInfo.processInfo.systemUptime
        let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
            || event.getIntegerValueField(.eventSourceStateID) == Int64(CGEventSourceStateID.privateState.rawValue)
        let evaluation = inspector.evaluate(
            point: event.location,
            modifiers: ModifierState(event.flags),
            isSynthetic: isSynthetic,
            configuration: config,
            isPenalized: { [penalties] pid in penalties.isPenalized(pid, now: now) }
        )

        switch evaluation.passReason {
        case .accessibilityTimeout?, .budgetExceeded?:
            if let pid = evaluation.pid { penalties.penalize(pid, now: now) }
        case .unknownApplication?:
            if let pid = evaluation.pid { post(.unknownApplication(pid)) }
        case .accessibilityDisabled?:
            post(.accessibilityUnavailable)
        default:
            break
        }
        // Ordinary clicks (content, other apps, modifiers) cost no main-thread
        // work at all; only title-bar clicks that reached Accessibility are reported.
        if evaluation.passReason?.reachedAccessibility ?? true { post(.evaluated(evaluation)) }

        let disposition: EventDisposition
        switch evaluation.result {
        case .success(let click): disposition = tracker.mouseDown(arm: click)
        case .failure: disposition = tracker.mouseDown(arm: nil)
        }
        setDragTracking(disposition == .swallow)
        return disposition
    }

    private func setDragTracking(_ enabled: Bool) {
        guard let dragTap, CGEvent.tapIsEnabled(tap: dragTap) != enabled else { return }
        CGEvent.tapEnable(tap: dragTap, enable: enabled)
    }

    private func post(_ notice: Notice) {
        DispatchQueue.main.async { [weak self] in self?.onNotice?(notice) }
    }
}

private func interceptorCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<MouseEventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handle(type: type, event: event)
}

extension ModifierState {
    init(_ flags: CGEventFlags) {
        var state: ModifierState = []
        if flags.contains(.maskShift) { state.insert(.shift) }
        if flags.contains(.maskControl) { state.insert(.control) }
        if flags.contains(.maskAlternate) { state.insert(.option) }
        if flags.contains(.maskCommand) { state.insert(.command) }
        self = state
    }
}
