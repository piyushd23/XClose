<div align="center">

# ⓧ XClose

### *Click the red × to actually quit the app.*

A lightweight macOS menu-bar utility that makes the close button behave the way you always expected.<br>
Click a window's red **×** and the whole app quits — exactly as if you pressed **⌘Q**.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Architecture](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-8E8E93?style=flat-square)](https://support.apple.com/en-us/HT211814)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-47%20Passing-2EA44F?style=flat-square)]()

</div>

---

## The Problem

On macOS, clicking the red **×** button doesn't quit the app — it just closes the window. The app keeps running invisibly in the background, consuming memory and resources. To actually quit, you have to remember **⌘Q** or right-click the Dock icon.

**XClose fixes this.** One click on the red **×** now quits the entire app, naturally.

## ✨ Features

| | |
|---|---|
| 🔴 **Click red × → App quits** | All windows close and the app runs its normal quit flow, asking to save unsaved work |
| ⌥ **Option-click to just close** | Hold Option to close only that window, preserving the original macOS behavior |
| 🛡️ **Respects save prompts** | XClose never force-quits. If an app has unsaved work, you'll see its save dialog |
| ⚡ **Instant visual feedback** | With *Hide while quitting*, apps vanish immediately while finishing in the background |
| 🎯 **Smart detection** | Uses Accessibility APIs — no pixel detection, no injection, no hacks |
| 🚫 **System apps excluded** | Finder, Dock, and system components are never affected |
| ⚙️ **Per-app control** | Exclude any app you want from the Settings panel |
| 🔒 **Privacy-first** | Everything stays on your Mac — no account, no network, no analytics |

## 📦 Installation

### Download

> **Coming soon** — Pre-built, signed and notarized releases will be available on the [Releases](https://github.com/piyushd23/XClose/releases) page.

### Build from Source

**Requirements:** macOS 13+, Xcode 16+ or Swift 5.9+ Command Line Tools

```bash
# Clone the repository
git clone https://github.com/piyushd23/XClose.git
cd XClose

# Run the test suite (47 unit tests)
swift test

# Build the universal app (Apple Silicon + Intel)
scripts/build-app.sh

# Launch
open dist/XClose.app
```

Or open `XClose.xcodeproj` in Xcode 16+ and run the **XClose** scheme.

### First Launch

1. XClose explains what changes
2. Grant **Accessibility** permission (the only permission needed)
3. Click **Enable XClose** — you're done!

The menu-bar icon shows the current state:
| Icon | State |
|---|---|
| **Filled ⓧ** | Active — red × clicks will quit apps |
| **Outlined ⓧ** | Paused or Starting |
| **⚠︎** | Permission required or Not working |

## 🏗️ How It Works

XClose intercepts mouse clicks using a macOS `CGEvent` tap, then uses the Accessibility API to verify whether the click landed on a real window close button. If it did, XClose swallows the click and sends a graceful `terminate()` request to the app — the same mechanism as **⌘Q**.

```
Mouse click → Event tap → Accessibility hit test → Is it a real red ×?
                                                      ├─ Yes → Swallow click, send terminate()
                                                      └─ No  → Pass through untouched
```

**Key design principles:**
- **Never force-quits** — uses `NSRunningApplication.terminate()`, so apps can show save dialogs
- **Never both closes and quits** — the click is either swallowed (and a quit is sent) or passed through (and the app handles it normally)
- **At most 4 IPC calls** per detection, each capped at 150ms
- **Yellow, green, ⌘W are never touched**

For the full technical deep dive, see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 📁 Project Structure

```
XClose/
├── Sources/
│   ├── XCloseCore/           # Pure logic — policy, click rules, sequencing (unit tested)
│   │   ├── AppIdentity.swift
│   │   ├── ApplicationPolicy.swift
│   │   ├── ClickRules.swift
│   │   ├── ClickSequenceTracker.swift
│   │   ├── OperationalState.swift
│   │   └── QuitRequestTracker.swift
│   └── XClose/               # App — event tap, Accessibility, UI
│       ├── XCloseApp.swift
│       ├── MouseEventInterceptor.swift
│       ├── AccessibilityService.swift
│       ├── QuitCoordinator.swift
│       ├── MenuBarController.swift
│       └── Views/
├── Tests/XCloseCoreTests/    # Swift Testing suites (47 tests)
├── Resources/                # Info.plist, entitlements, icons
├── scripts/                  # build-app.sh, notarize.sh, make-icon.swift
├── docs/                     # Architecture, testing, distribution
└── Package.swift             # Swift Package Manager manifest
```

## 🧪 Testing

```bash
swift test    # Runs all 47 unit tests
```

The test suite covers:
- **Click validation** — button roles, subroles, ownership, geometry
- **Click sequencing** — press/release tracking, drag cancellation, double-click dedup
- **Quit requests** — timing, confirmation, cancellation, pid reuse protection
- **Operational state** — permission, pause, tap health state machine
- **Application policy** — exclusion rules, protected apps

See [TESTING.md](docs/TESTING.md) for the full automated results and the manual compatibility matrix.

## 📖 Documentation

| Document | Description |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Interception pipeline, ownership model, failure handling |
| [TESTING.md](docs/TESTING.md) | Automated test results and manual compatibility matrix |
| [DISTRIBUTION.md](docs/DISTRIBUTION.md) | Signing, notarization, installation, and uninstallation |

## ⚠️ Known Limitations

- **Custom window controls** — Frameless apps with HTML-drawn buttons keep their normal behavior
- **Panels & dialogs** — Red × on Inspector or Settings panels only closes that window (by design)
- **No pressed state** — The red × doesn't show its pressed look since XClose swallows the click
- **Unresponsive apps** — Clicks pass through after ~400ms, with a 5s penalty cooldown
- **Synthetic clicks** — Clicks from other automation tools pass through untouched

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run the tests (`swift test`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Made with ❤️ for macOS users who just want the red × to work.**

</div>
