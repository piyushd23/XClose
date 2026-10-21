#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: renders onboarding and every settings pane, in light and dark
/// appearance, to PNG files. Run a debug build with XCLOSE_SNAPSHOTS=<dir>.
@MainActor
enum Snapshotter {
    static func run(into directory: URL) {
        let model = AppModel()
        model.lifecycle.start()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for tab in SettingsTab.allCases {
                let router = SettingsRouter()
                router.tab = tab
                render(SettingsView(router: router), model: model, appearance: appearance,
                       to: directory.appendingPathComponent("settings-\(tab.title.lowercased())-\(appearanceName).png"))
            }
            for step in 0..<3 {
                let view = OnboardingView(onFinish: {}, initialStep: step)
                render(view, model: model, appearance: appearance,
                       to: directory.appendingPathComponent("onboarding-\(step + 1)-\(appearanceName).png"))
            }
        }
    }

    private static func render<V: View>(_ view: V, model: AppModel, appearance: NSAppearance.Name, to url: URL) {
        let root = view
            .environmentObject(model)
            .environmentObject(model.policyStore)
            .environmentObject(model.permissions)
            .environmentObject(model.lifecycle)
            .environmentObject(model.diagnostics)
            .environmentObject(model.launchAtLogin)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        // Opaque backdrop so sidebar materials (which need a real window) aren't transparent.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (appearance == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        host.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
#endif
