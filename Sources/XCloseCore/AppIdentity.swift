import Foundation

/// Stable identity used to persist per-application preferences.
///
/// Bundle identifiers are preferred. Applications without one (rare: some Java
/// launchers, bare executables) fall back to the standardized path of their
/// bundle or executable. Display names are never used as identity.
public enum AppKey: Hashable, Codable, Sendable, CustomStringConvertible {
    case bundleID(String)
    case path(String)

    public var description: String {
        switch self {
        case .bundleID(let id): return id
        case .path(let path): return path
        }
    }

    /// Bundle identifiers are case-insensitive in Launch Services; normalize so
    /// that persisted exclusions match regardless of how the app reports it.
    public var normalized: AppKey {
        switch self {
        case .bundleID(let id): return .bundleID(id.lowercased())
        case .path(let path): return .path((path as NSString).standardizingPath)
        }
    }
}

/// A platform-neutral snapshot of a running application.
public struct AppDescriptor: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    /// Path of the .app bundle, or of the executable for unbundled apps.
    public var bundlePath: String?
    public var name: String
    /// True when the app uses the regular activation policy (Dock icon, menu bar).
    public var isRegularApp: Bool

    public init(pid: Int32, bundleID: String?, bundlePath: String?, name: String, isRegularApp: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.name = name
        self.isRegularApp = isRegularApp
    }

    public var key: AppKey? {
        if let bundleID, !bundleID.isEmpty { return AppKey.bundleID(bundleID).normalized }
        if let bundlePath, !bundlePath.isEmpty { return AppKey.path(bundlePath).normalized }
        return nil
    }
}
