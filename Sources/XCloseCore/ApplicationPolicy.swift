import Foundation

public enum IneligibilityReason: String, Sendable, CaseIterable {
    case selfApp
    case protectedSystemApp
    case notRegularApp
    case noStableIdentity
    case excludedByUser

    public var summary: String {
        switch self {
        case .selfApp: return "XClose itself"
        case .protectedSystemApp: return "Protected system component"
        case .notRegularApp: return "Background or menu-bar app"
        case .noStableIdentity: return "No bundle identifier or path"
        case .excludedByUser: return "Excluded by you"
        }
    }
}

public enum AppEligibility: Equatable, Sendable {
    case eligible
    case ineligible(IneligibilityReason)

    public var isEligible: Bool { self == .eligible }
}

/// Decides whether red × should quit a given application. Pure value type so it
/// can be evaluated off the main thread and unit tested without AppKit.
public struct ApplicationPolicy: Equatable, Sendable {
    /// System components whose windows must never be turned into a quit request.
    /// Most of them are not regular apps anyway; listing them is defense in depth.
    public static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.windowmanager",
        "com.apple.spotlight",
        "com.apple.securityagent",
        "com.apple.coreservices.uiagent",
        "com.apple.usernotificationcenter",
        "com.apple.screensaver.engine",
        "com.apple.screencaptureui",
        "com.apple.textinputmenuagent",
        "com.apple.universalaccessauthwarn",
        "com.apple.backgroundtaskmanagementagent",
        "com.apple.wifi.wifiagent",
        "com.apple.ctkahp",
    ]

    public var ownBundleID: String?
    public var ownPID: Int32?
    public var exclusions: Set<AppKey>

    public init(ownBundleID: String? = nil, ownPID: Int32? = nil, exclusions: Set<AppKey> = []) {
        self.ownBundleID = ownBundleID?.lowercased()
        self.ownPID = ownPID
        self.exclusions = Set(exclusions.map(\.normalized))
    }

    public static func isProtected(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return protectedBundleIDs.contains(bundleID.lowercased())
    }

    public func eligibility(of app: AppDescriptor) -> AppEligibility {
        if let ownPID, app.pid == ownPID { return .ineligible(.selfApp) }
        if let ownBundleID, app.bundleID?.lowercased() == ownBundleID { return .ineligible(.selfApp) }
        if Self.isProtected(bundleID: app.bundleID) { return .ineligible(.protectedSystemApp) }
        guard app.isRegularApp else { return .ineligible(.notRegularApp) }
        guard let key = app.key else { return .ineligible(.noStableIdentity) }
        if exclusions.contains(key) { return .ineligible(.excludedByUser) }
        // An app with a bundle ID may also have been excluded by path (e.g. it was
        // added while it lacked an identifier, or from a copy at another location).
        if let path = app.bundlePath, exclusions.contains(AppKey.path(path).normalized) {
            return .ineligible(.excludedByUser)
        }
        return .eligible
    }
}
