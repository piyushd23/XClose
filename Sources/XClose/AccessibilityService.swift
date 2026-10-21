import ApplicationServices
import CoreGraphics
import Foundation
import XCloseCore

/// Bounded Accessibility queries used to identify a window's close control.
///
/// Thread-safe: holds only the immutable system-wide element. Every call is an
/// IPC round trip to the target app, so the number of calls per click is fixed
/// (at most four) and each is capped by the process-wide messaging timeout.
final class AccessibilityService: @unchecked Sendable {
    /// Applied to every AX call made by this process.
    static let messagingTimeout: Float = 0.15

    private let systemWide = AXUIElementCreateSystemWide()

    init() {
        // Setting the timeout on the system-wide element applies it globally.
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
    }

    private static let buttonAttributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXEnabledAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXWindowAttribute, kAXParentAttribute,
    ] as [String]
    private static let windowAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXCloseButtonAttribute] as [String]

    /// Hit-tests `point` (top-left global coordinates) and describes the close
    /// button there, if any. `deadline` is a `DispatchTime.now().uptimeNanoseconds` value.
    func closeButtonFacts(at point: CGPoint, deadline: UInt64) -> Result<CloseButtonFacts, PassReason> {
        var hit: AXUIElement?
        let hitError = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
        guard hitError == .success, let hitElement = hit else { return .failure(Self.reason(for: hitError)) }

        var button = hitElement
        var attributes: [String: AnyObject]
        switch copyAttributes(button, Self.buttonAttributes) {
        case .success(let values): attributes = values
        case .failure(let reason): return .failure(reason)
        }

        if !Self.isCloseButton(attributes) {
            // Some toolkits report a child image of the button. Walk up one level,
            // and only from roles that can plausibly sit inside a button.
            let role = attributes[kAXRoleAttribute] as? String
            guard role == kAXImageRole || role == kAXUnknownRole,
                  let parent = Self.element(attributes[kAXParentAttribute]) else {
                return .failure(.notCloseButton)
            }
            guard DispatchTime.now().uptimeNanoseconds < deadline else { return .failure(.budgetExceeded) }
            switch copyAttributes(parent, Self.buttonAttributes) {
            case .success(let values): attributes = values
            case .failure(let reason): return .failure(reason)
            }
            guard Self.isCloseButton(attributes) else { return .failure(.notCloseButton) }
            button = parent
        }

        guard let window = Self.element(attributes[kAXWindowAttribute]) else { return .failure(.notWindowCloseButton) }
        guard DispatchTime.now().uptimeNanoseconds < deadline else { return .failure(.budgetExceeded) }
        let windowValues: [String: AnyObject]
        switch copyAttributes(window, Self.windowAttributes) {
        case .success(let values): windowValues = values
        case .failure(let reason): return .failure(reason)
        }

        let isOwn = Self.element(windowValues[kAXCloseButtonAttribute]).map { CFEqual($0, button) } ?? false
        var pid: pid_t = 0
        guard AXUIElementGetPid(button, &pid) == .success else { return .failure(.accessibilityError) }

        var frame: CGRect?
        if let origin = Self.point(attributes[kAXPositionAttribute]), let size = Self.size(attributes[kAXSizeAttribute]) {
            frame = CGRect(origin: origin, size: size)
        }

        return .success(CloseButtonFacts(
            role: attributes[kAXRoleAttribute] as? String,
            subrole: attributes[kAXSubroleAttribute] as? String,
            isEnabled: (attributes[kAXEnabledAttribute] as? NSNumber)?.boolValue,
            frame: frame,
            pid: pid,
            windowRole: windowValues[kAXRoleAttribute] as? String,
            windowSubrole: windowValues[kAXSubroleAttribute] as? String,
            isWindowsOwnCloseButton: isOwn
        ))
    }

    // MARK: - Helpers

    private func copyAttributes(_ element: AXUIElement, _ names: [String]) -> Result<[String: AnyObject], PassReason> {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard error == .success, let array = values as [AnyObject]? else { return .failure(Self.reason(for: error)) }
        var result: [String: AnyObject] = [:]
        for (index, value) in array.enumerated() where index < names.count {
            // Missing attributes come back as an AXValue wrapping an AXError.
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { continue }
            result[names[index]] = value
        }
        return .success(result)
    }

    private static func isCloseButton(_ attributes: [String: AnyObject]) -> Bool {
        attributes[kAXRoleAttribute] as? String == kAXButtonRole
            && attributes[kAXSubroleAttribute] as? String == kAXCloseButtonSubrole
    }

    private static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private static func reason(for error: AXError) -> PassReason {
        switch error {
        case .cannotComplete: return .accessibilityTimeout
        case .apiDisabled: return .accessibilityDisabled
        case .noValue, .attributeUnsupported: return .notCloseButton
        default: return .accessibilityError
        }
    }
}
