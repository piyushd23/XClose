import CoreGraphics
import Foundation
import XCloseCore

struct AppEntry: Equatable, Sendable {
    var descriptor: AppDescriptor
    var eligibility: AppEligibility
}

/// Lock-protected snapshot shared with the event-tap thread.
struct InterceptorConfiguration: Sendable {
    var isActive = false
    var apps: [Int32: AppEntry] = [:]
}

struct ClickEvaluation: Sendable {
    var result: Result<ArmedClick, PassReason>
    var pid: Int32?
    var appName: String?
    var elapsedMilliseconds: Double

    var passReason: PassReason? {
        if case .failure(let reason) = result { return reason }
        return nil
    }
}

/// The full decision pipeline for one mouse-down, shared by the event tap and the
/// Diagnostics "test pointer target" tool. Stateless apart from the AX service.
final class ClickInspector: @unchecked Sendable {
    /// Overall budget for the Accessibility stage, checked between calls.
    static let budget: UInt64 = 250_000_000

    private let accessibility = AccessibilityService()

    func evaluate(point: CGPoint, modifiers: ModifierState, isSynthetic: Bool,
                  configuration: InterceptorConfiguration, isPenalized: (Int32) -> Bool) -> ClickEvaluation {
        let start = DispatchTime.now().uptimeNanoseconds
        func finish(_ result: Result<ArmedClick, PassReason>, _ entry: AppEntry? = nil, pid: Int32? = nil) -> ClickEvaluation {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            return ClickEvaluation(result: result, pid: entry?.descriptor.pid ?? pid,
                                   appName: entry?.descriptor.name, elapsedMilliseconds: elapsed)
        }

        if let reason = ClickRules.precheck(isActive: configuration.isActive, isSynthetic: isSynthetic, modifiers: modifiers) {
            return finish(.failure(reason))
        }
        guard let hint = Self.windowHint(at: point, apps: configuration.apps) else {
            return finish(.failure(.noWindowUnderPointer))
        }
        let entry = configuration.apps[hint.pid]
        guard ClickRules.isInTitleBarBand(point: point, windowBounds: hint.bounds) else {
            return finish(.failure(.outsideTitleBar), entry, pid: hint.pid)
        }
        guard let entry else { return finish(.failure(.unknownApplication), pid: hint.pid) }
        guard entry.eligibility.isEligible else { return finish(.failure(.ineligibleApplication), entry) }
        guard !isPenalized(hint.pid) else { return finish(.failure(.unresponsiveApplication), entry) }

        let facts: CloseButtonFacts
        switch accessibility.closeButtonFacts(at: point, deadline: start + Self.budget) {
        case .success(let value): facts = value
        case .failure(let reason): return finish(.failure(reason), entry)
        }
        switch ClickRules.validate(facts, point: point, expectedPID: hint.pid) {
        case .failure(let reason):
            return finish(.failure(reason), entry)
        case .success(let frame):
            let armed = ArmedClick(pid: hint.pid, appKey: entry.descriptor.key, appName: entry.descriptor.name,
                                   buttonFrame: frame, armedAt: ProcessInfo.processInfo.systemUptime)
            return finish(.success(armed), entry)
        }
    }

    struct WindowHint {
        var pid: Int32
        var bounds: CGRect
    }

    /// Finds the window that should receive a click at `point`, front to back.
    ///
    /// The window list includes transparent system overlays (the Dock owns a
    /// full-screen window above all apps), so windows above layer 0 count only when
    /// they belong to a known regular app (floating panels, full-screen title bars).
    /// The result is a hint: Accessibility hit-testing remains authoritative and
    /// must report the same process.
    static func windowHint(at point: CGPoint, apps: [Int32: AppEntry]) -> WindowHint? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let pid = pidNumber.int32Value
            if layer != 0 && apps[pid]?.descriptor.isRegularApp != true { continue }
            return WindowHint(pid: pid, bounds: bounds)
        }
        return nil
    }
}
