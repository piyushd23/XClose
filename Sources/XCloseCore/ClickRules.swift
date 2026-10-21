import CoreGraphics
import Foundation

public struct ModifierState: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = ModifierState(rawValue: 1 << 0)
    public static let control = ModifierState(rawValue: 1 << 1)
    public static let option = ModifierState(rawValue: 1 << 2)
    public static let command = ModifierState(rawValue: 1 << 3)
}

/// Why a mouse-down was left untouched. Every path that is not a confident
/// red × detection ends in one of these and the click passes through normally.
public enum PassReason: String, Error, Sendable, CaseIterable {
    case inactive
    case syntheticEvent
    case optionBypass
    case otherModifier
    case noWindowUnderPointer
    case outsideTitleBar
    case unknownApplication
    case ineligibleApplication
    case unresponsiveApplication
    case accessibilityDisabled
    case accessibilityTimeout
    case accessibilityError
    case budgetExceeded
    case notCloseButton
    case notWindowCloseButton
    case notStandardWindow
    case closeButtonDisabled
    case ownerMismatch
    case pointOutsideButton

    public var summary: String {
        switch self {
        case .inactive: return "XClose not active"
        case .syntheticEvent: return "Synthetic event"
        case .optionBypass: return "Option-click bypass"
        case .otherModifier: return "Modifier key held"
        case .noWindowUnderPointer: return "No window under pointer"
        case .outsideTitleBar: return "Outside title-bar area"
        case .unknownApplication: return "Application not yet known"
        case .ineligibleApplication: return "Application excluded or protected"
        case .unresponsiveApplication: return "Application recently unresponsive"
        case .accessibilityDisabled: return "Accessibility access unavailable"
        case .accessibilityTimeout: return "Accessibility query timed out"
        case .accessibilityError: return "Accessibility query failed"
        case .budgetExceeded: return "Detection exceeded time budget"
        case .notCloseButton: return "Not a close button"
        case .notWindowCloseButton: return "Button is not the window's close control"
        case .notStandardWindow: return "Panel, dialog or sheet"
        case .closeButtonDisabled: return "Close button disabled"
        case .ownerMismatch: return "Window owner did not match"
        case .pointOutsideButton: return "Point outside button bounds"
        }
    }

    /// Reasons that indicate the Accessibility stage actually ran (worth logging).
    public var reachedAccessibility: Bool {
        switch self {
        case .inactive, .syntheticEvent, .optionBypass, .otherModifier, .noWindowUnderPointer,
             .outsideTitleBar, .unknownApplication, .ineligibleApplication, .unresponsiveApplication:
            return false
        default:
            return true
        }
    }
}

/// Facts gathered from Accessibility about the element under a click.
public struct CloseButtonFacts: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var isEnabled: Bool?
    public var frame: CGRect?
    public var pid: Int32
    public var windowRole: String?
    public var windowSubrole: String?
    /// The element is CFEqual to its window's kAXCloseButtonAttribute value.
    public var isWindowsOwnCloseButton: Bool

    public init(role: String?, subrole: String?, isEnabled: Bool?, frame: CGRect?, pid: Int32,
                windowRole: String?, windowSubrole: String?, isWindowsOwnCloseButton: Bool) {
        self.role = role
        self.subrole = subrole
        self.isEnabled = isEnabled
        self.frame = frame
        self.pid = pid
        self.windowRole = windowRole
        self.windowSubrole = windowSubrole
        self.isWindowsOwnCloseButton = isWindowsOwnCloseButton
    }
}

public enum ClickRules {
    // Accessibility constant values (kAXButtonRole etc.), duplicated here so the
    // core module stays free of ApplicationServices.
    public static let buttonRole = "AXButton"
    public static let closeButtonSubrole = "AXCloseButton"
    public static let windowRole = "AXWindow"
    public static let standardWindowSubrole = "AXStandardWindow"

    /// Vertical band below a window's top edge where a close control can live.
    /// Only a cheap pre-filter that avoids Accessibility IPC for content clicks;
    /// the decision itself is always made from Accessibility semantics.
    public static let titleBarBand: CGFloat = 80
    /// Slack when deciding whether the release happened on the button.
    public static let hitTolerance: CGFloat = 2

    /// Cheap checks done before touching the window server or Accessibility.
    public static func precheck(isActive: Bool, isSynthetic: Bool, modifiers: ModifierState) -> PassReason? {
        if !isActive { return .inactive }
        if isSynthetic { return .syntheticEvent }
        if modifiers.contains(.option) { return .optionBypass }
        if !modifiers.isEmpty { return .otherModifier }
        return nil
    }

    /// Both rects use top-left-origin global display coordinates (Quartz/AX).
    public static func isInTitleBarBand(point: CGPoint, windowBounds: CGRect) -> Bool {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return false }
        guard point.x >= windowBounds.minX, point.x <= windowBounds.maxX else { return false }
        return point.y >= windowBounds.minY - hitTolerance && point.y <= windowBounds.minY + titleBarBand
    }

    /// Decides whether the facts describe the red × of a standard window owned by
    /// `expectedPID`. Returns the button frame to use for release hit-testing.
    public static func validate(_ facts: CloseButtonFacts, point: CGPoint, expectedPID: Int32) -> Result<CGRect, PassReason> {
        guard facts.role == buttonRole, facts.subrole == closeButtonSubrole else { return .failure(.notCloseButton) }
        guard facts.isWindowsOwnCloseButton else { return .failure(.notWindowCloseButton) }
        guard facts.windowRole == windowRole, facts.windowSubrole == standardWindowSubrole else {
            return .failure(.notStandardWindow)
        }
        // Unknown enabled state is treated as uncertain.
        guard facts.isEnabled == true else { return .failure(.closeButtonDisabled) }
        guard facts.pid == expectedPID, facts.pid > 0 else { return .failure(.ownerMismatch) }
        guard let frame = facts.frame, frame.width > 0, frame.height > 0 else { return .failure(.accessibilityError) }
        guard frame.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(point) else {
            return .failure(.pointOutsideButton)
        }
        return .success(frame)
    }
}
