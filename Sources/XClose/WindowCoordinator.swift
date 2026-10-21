import AppKit
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case general, applications, permissions, diagnostics, about
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let router = SettingsRouter()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func showSettings(tab: SettingsTab) {
        router.tab = tab
        if settingsWindow == nil {
            let view = SettingsView(router: router)
                .environmentObject(model)
                .environmentObject(model.policyStore)
                .environmentObject(model.permissions)
                .environmentObject(model.lifecycle)
                .environmentObject(model.diagnostics)
                .environmentObject(model.launchAtLogin)
            settingsWindow = makeWindow(title: "XClose Settings", content: view)
        }
        present(settingsWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(onFinish: { [weak self] in
                self?.onboardingWindow?.close()
            })
            .environmentObject(model)
            .environmentObject(model.policyStore)
            .environmentObject(model.permissions)
            onboardingWindow = makeWindow(title: "Welcome to XClose", content: view)
        }
        present(onboardingWindow)
    }

    /// Closed windows are released (with their SwiftUI views and subscriptions) so
    /// that XClose stays small in the background.
    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Defer so the window finishes closing before its controller is released.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                if self?.settingsWindow === window { self?.settingsWindow = nil }
                if self?.onboardingWindow === window { self?.onboardingWindow = nil }
            }
        }
    }

    private func present(_ window: NSWindow?) {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
