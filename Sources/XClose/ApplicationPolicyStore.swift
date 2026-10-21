import AppKit
import XCloseCore

struct ExclusionEntry: Codable, Hashable, Identifiable {
    var key: AppKey
    var displayName: String
    var path: String?

    var id: AppKey { key }
}

/// Persists user preferences in UserDefaults. Exclusions are keyed by bundle
/// identifier, falling back to the bundle/executable path for apps without one.
@MainActor
final class ApplicationPolicyStore: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    /// Hide an app as soon as its quit is requested, so red × feels instant.
    @Published var hidesWhileQuitting: Bool {
        didSet { defaults.set(hidesWhileQuitting, forKey: Keys.hidesWhileQuitting) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    @Published private(set) var exclusions: [ExclusionEntry] {
        didSet { persistExclusions() }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "enabled"
        static let onboarding = "hasCompletedOnboarding"
        static let exclusions = "exclusions.v1"
        static let hidesWhileQuitting = "hidesWhileQuitting"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Disabled until onboarding enables it.
        isEnabled = defaults.bool(forKey: Keys.enabled)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        hidesWhileQuitting = defaults.object(forKey: Keys.hidesWhileQuitting) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.exclusions),
           let decoded = try? JSONDecoder().decode([ExclusionEntry].self, from: data) {
            exclusions = decoded
        } else {
            exclusions = []
        }
    }

    func policy() -> ApplicationPolicy {
        ApplicationPolicy(
            ownBundleID: Bundle.main.bundleIdentifier,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            exclusions: Set(exclusions.map(\.key))
        )
    }

    func isExcluded(_ key: AppKey) -> Bool {
        exclusions.contains { $0.key == key.normalized }
    }

    func exclude(key: AppKey, displayName: String, path: String?) {
        let key = key.normalized
        guard !isExcluded(key) else { return }
        exclusions.append(ExclusionEntry(key: key, displayName: displayName, path: path))
        exclusions.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func exclude(_ app: AppDescriptor) {
        guard let key = app.key else { return }
        exclude(key: key, displayName: app.name, path: app.bundlePath)
    }

    /// Adds an exclusion for an .app chosen on disk, without launching it.
    func exclude(appAt url: URL) {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let key: AppKey = bundle?.bundleIdentifier.map { .bundleID($0) } ?? .path(url.path)
        exclude(key: key, displayName: name, path: url.path)
    }

    func removeExclusion(_ key: AppKey) {
        exclusions.removeAll { $0.key == key.normalized }
    }

    private func persistExclusions() {
        if let data = try? JSONEncoder().encode(exclusions) {
            defaults.set(data, forKey: Keys.exclusions)
        }
    }
}
