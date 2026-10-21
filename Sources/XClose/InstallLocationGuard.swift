import AppKit

/// Makes sure XClose runs from a stable location. From the disk image, or from a
/// quarantined download that macOS runs from a randomized read-only path ("app
/// translocation"), the Accessibility grant and Sparkle updates do not work.
@MainActor
enum InstallLocationGuard {
    /// Returns false when XClose is relaunching from Applications or quitting.
    static func ensureInstalled() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let path = bundleURL.path
        if path.contains("/AppTranslocation/") {
            showTranslocationHelp()
            return false
        }
        if path.hasPrefix("/Volumes/") {
            return !offerCopyToApplications(from: bundleURL)
        }
        return true
    }

    private static func offerCopyToApplications(from source: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Copy XClose to Applications?"
        alert.informativeText = "XClose is running from the disk image. It needs to be in your Applications folder to keep its permission and receive updates."
        alert.addButton(withTitle: "Copy to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            // The user already approved this app when opening it from the disk
            // image; don't make Gatekeeper ask again for the identical copy.
            removexattr(destination.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't copy XClose"
            failure.informativeText = "Drag XClose from the disk image into your Applications folder, then open it from there.\n\n\(error.localizedDescription)"
            failure.runModal()
            NSApp.terminate(nil)
            return true
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    private static func showTranslocationHelp() {
        let alert = NSAlert()
        alert.messageText = "Move XClose to Applications"
        alert.informativeText = "macOS is running XClose from a temporary location. Drag XClose into your Applications folder, then open it from there."
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
