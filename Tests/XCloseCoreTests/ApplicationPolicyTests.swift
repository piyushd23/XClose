import Testing
import XCloseCore

private func app(_ bundleID: String?, pid: Int32 = 100, path: String? = "/Applications/Example.app",
                 regular: Bool = true, name: String = "Example") -> AppDescriptor {
    AppDescriptor(pid: pid, bundleID: bundleID, bundlePath: path, name: name, isRegularApp: regular)
}

@Suite("Application policy")
struct ApplicationPolicyTests {
    @Test func regularAppIsEligibleByDefault() {
        #expect(ApplicationPolicy().eligibility(of: app("com.apple.TextEdit")) == .eligible)
    }

    @Test(arguments: ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow",
                      "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.WindowManager"])
    func protectedSystemComponentsAreAlwaysExcluded(bundleID: String) {
        #expect(ApplicationPolicy().eligibility(of: app(bundleID)) == .ineligible(.protectedSystemApp))
    }

    @Test func finderIsProtectedEvenAsRegularAppWithUnusualCase() {
        #expect(ApplicationPolicy().eligibility(of: app("com.apple.Finder")) == .ineligible(.protectedSystemApp))
    }

    @Test func xcloseItselfIsExcludedByBundleIDAndPID() {
        let policy = ApplicationPolicy(ownBundleID: "app.xclose.XClose", ownPID: 42)
        #expect(policy.eligibility(of: app("app.xclose.xclose", pid: 7)) == .ineligible(.selfApp))
        #expect(policy.eligibility(of: app("com.other", pid: 42)) == .ineligible(.selfApp))
    }

    @Test func backgroundAndMenuBarAppsAreNotTargets() {
        #expect(ApplicationPolicy().eligibility(of: app("com.example.agent", regular: false)) == .ineligible(.notRegularApp))
    }

    @Test func userExclusionByBundleIDIsCaseInsensitive() {
        let policy = ApplicationPolicy(exclusions: [.bundleID("com.Google.Chrome")])
        #expect(policy.eligibility(of: app("com.google.chrome")) == .ineligible(.excludedByUser))
        #expect(policy.eligibility(of: app("com.apple.Safari")) == .eligible)
    }

    @Test func appsWithoutBundleIDFallBackToPath() {
        let java = app(nil, path: "/opt/tools/Launcher.app")
        #expect(java.key == .path("/opt/tools/Launcher.app"))
        #expect(ApplicationPolicy().eligibility(of: java) == .eligible)
        let policy = ApplicationPolicy(exclusions: [.path("/opt/tools/./Launcher.app")])
        #expect(policy.eligibility(of: java) == .ineligible(.excludedByUser))
    }

    @Test func appWithNoIdentityIsNotTargeted() {
        #expect(ApplicationPolicy().eligibility(of: app(nil, path: nil)) == .ineligible(.noStableIdentity))
    }

    @Test func displayNameIsNotIdentity() {
        // Two different apps sharing a name must not share an exclusion.
        let policy = ApplicationPolicy(exclusions: [.bundleID("com.vendor.notes")])
        #expect(policy.eligibility(of: app("com.apple.Notes", name: "Notes")) == .eligible)
    }

    @Test func appKeyRoundTripsThroughCodable() throws {
        let keys: [AppKey] = [.bundleID("com.apple.Safari"), .path("/Applications/Tool.app")]
        let data = try JSONEncoder().encode(keys)
        #expect(try JSONDecoder().decode([AppKey].self, from: data) == keys)
    }
}

import Foundation
