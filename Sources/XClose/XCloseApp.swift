import AppKit

@main
enum XCloseMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var windows: WindowCoordinator?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["XCLOSE_SNAPSHOTS"] {
            Snapshotter.run(into: URL(fileURLWithPath: directory))
            exit(0)
        }
        #endif
        // Two interceptors would fight over the same clicks.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        NSApp.mainMenu = Self.makeMainMenu()
        let model = AppModel()
        let windows = WindowCoordinator(model: model)
        self.model = model
        self.windows = windows
        menuBar = MenuBarController(model: model, windows: windows)
        model.start()

        if !model.policyStore.hasCompletedOnboarding {
            windows.showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showSettings(tab: .general)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore normal click behavior before the process exits. (If XClose
        // crashes instead, the kernel tears the tap down with the process.)
        model?.shutdown()
    }

    /// Minimal menu so ⌘W, ⌘Q, copy and paste work in XClose's own windows.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit XClose", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }
}
