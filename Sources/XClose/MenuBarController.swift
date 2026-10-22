import AppKit
import Combine
import XCloseCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let windows: WindowCoordinator
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables: Set<AnyCancellable> = []
    /// Accent-colored dot over the icon while an update is waiting. A separate
    /// view, so the icon itself stays a template image tinted by macOS.
    private let updateBadge: NSView = {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.layer?.cornerRadius = 3.5
        dot.layer?.borderWidth = 1
        dot.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        dot.isHidden = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        return dot
    }()

    init(model: AppModel, windows: WindowCoordinator) {
        self.model = model
        self.windows = windows
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        model.$state.sink { [weak self] state in self?.updateIcon(for: state) }.store(in: &cancellables)
        if let button = statusItem.button {
            button.addSubview(updateBadge)
            NSLayoutConstraint.activate([
                updateBadge.widthAnchor.constraint(equalToConstant: 7),
                updateBadge.heightAnchor.constraint(equalToConstant: 7),
                updateBadge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                updateBadge.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
            ])
        }
        model.updates.$pendingUpdateVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] version in self?.showUpdateBadge(version) }
            .store(in: &cancellables)
    }

    /// The star on a solid tile is the only menu-bar icon. It is a template image,
    /// so macOS tints it to the menu bar; it is dimmed whenever XClose is not
    /// actively quitting apps, and the menu shows the exact state.
    private static let glyph: NSImage? = {
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }()

    private func updateIcon(for state: OperationalState) {
        let button = statusItem.button
        button?.image = Self.glyph ?? NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        button?.image?.isTemplate = true
        button?.setAccessibilityLabel("XClose: \(state.title)")
        button?.appearsDisabled = state != .operational
        if model.updates.pendingUpdateVersion == nil { button?.toolTip = "XClose — \(state.title)" }
    }

    private func showUpdateBadge(_ version: String?) {
        updateBadge.isHidden = version == nil
        updateBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        statusItem.button?.toolTip = version.map { "XClose — Update \($0) available" } ?? "XClose — \(model.state.title)"
    }

    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    private static func color(for state: OperationalState) -> NSColor {
        switch state {
        case .operational: return .systemGreen
        case .paused, .starting: return .tertiaryLabelColor
        case .permissionRequired: return .systemOrange
        case .degraded: return .systemRed
        }
    }

    // Built when opened, so it always reflects current state without observers.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = model.state

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let title = NSMutableAttributedString(string: "XClose  ",
                                              attributes: [.font: NSFont.menuFont(ofSize: 0).bold])
        title.append(NSAttributedString(string: state.title,
                                        attributes: [.font: NSFont.menuFont(ofSize: 0),
                                                     .foregroundColor: NSColor.secondaryLabelColor]))
        status.attributedTitle = title
        status.image = Self.dot(Self.color(for: state))
        status.isEnabled = false
        menu.addItem(status)
        if case .degraded(let reason) = state {
            let detail = NSMenuItem(title: reason.summary, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: model.isEnabled ? "Pause XClose" : "Turn On XClose",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: model.isEnabled ? "pause.circle" : "play.circle", accessibilityDescription: nil)
        menu.addItem(toggle)

        switch state {
        case .permissionRequired:
            menu.addItem(item("Allow Accessibility Access…", #selector(openPermissions)))
        case .degraded:
            menu.addItem(item("Try Again", #selector(retry)))
        default:
            break
        }
        if state == .operational {
            let hint = NSMenuItem(title: "⌥-click red × to close only the window", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())
        if let version = model.updates.pendingUpdateVersion {
            let update = item("Update Available: \(version)…", #selector(checkForUpdates))
            update.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(update)
        }
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        if UpdateManager.isConfigured {
            let check = item("Check for Updates…", #selector(checkForUpdates))
            check.isEnabled = model.updates.canCheckForUpdates
            menu.addItem(check)
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit XClose", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() { model.toggleEnabled() }
    @objc private func openPermissions() { windows.showSettings(tab: .permissions) }
    @objc private func retry() { model.retryInterception() }
    @objc private func openSettings() { windows.showSettings(tab: .general) }
    @objc private func checkForUpdates() { model.updates.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
