<div align="center">

# XClose

**Native window close button enhancement for macOS**

A lightweight menu-bar utility that ensures clicking a window's red close button quits the application, matching the behavior of Command-Q.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Architecture](https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-8E8E93?style=flat-square)](https://support.apple.com/en-us/HT211814)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-47%20Passed-2EA44F?style=flat-square)]()

</div>

---

## Overview

On macOS, clicking the red close button on a window typically closes only that window while leaving the parent process running in the background. Terminating the application completely requires explicitly pressing **Command-Q** or quitting via the Dock or application menu.

**XClose changes this behavior.** Clicking the standard red close button terminates the entire application cleanly.

## Key Features

| Capability | Technical Detail |
|---|---|
| **Terminate on Close** | Closes all application windows and invokes standard termination lifecycle (`NSRunningApplication.terminate`). |
| **Option-Click Bypass** | Holding the Option key (`⌥`) preserves standard macOS behavior, closing only the targeted window. |
| **Safe Exit Lifecycle** | Never sends unhandled POSIX termination signals (`SIGKILL`). Native save prompts and confirmation dialogs remain fully functional. |
| **Instant Visual Feedback** | Optionally hides the application window immediately while the process completes shutdown in the background. Automatically restores visibility if user attention is required. |
| **Deterministic Accessibility Hit-Testing** | Validates window roles and close button attributes through macOS Accessibility APIs rather than screen coordinate heuristics or code injection. |
| **Protected System Processes** | System processes such as Finder, Dock, and core UI components are strictly excluded from interception. |
| **Configurable Application Rules** | Custom exclusion rules allow specific applications to retain default window management behavior. |
| **Automatic Updates** | Sparkle 2 delivers EdDSA-signed updates from GitHub Releases; every update is verified before installation. |
| **Privacy by Design** | Operates locally. No telemetry, accounts, background daemons, or user tracking. The only network request is an optional daily update check. |

## Installation

### Download

**[Download XClose.dmg](https://github.com/piyushd23/XClose/releases/latest/download/XClose.dmg)** · [Website](https://piyushd23.github.io/XClose/) · [All releases](https://github.com/piyushd23/XClose/releases)

1. Open `XClose.dmg` and drag **XClose** into **Applications**.
2. Open XClose. Releases are not yet notarized by Apple, so on first launch macOS reports that it cannot verify the developer. Open **System Settings > Privacy & Security**, scroll to the message about XClose, and select **Open Anyway**.
3. Follow the onboarding to grant **Accessibility** access.

XClose then keeps itself up to date. Releases are signed with a stable project certificate, so the Accessibility grant persists across updates.

### Building from Source

**Prerequisites:**
- macOS 13.0 (Ventura) or later
- Xcode 16+ or Swift 5.9+ Command Line Tools

```bash
# Clone the repository
git clone https://github.com/piyushd23/XClose.git
cd XClose

# Run test suite
swift test

# Build universal binary (arm64 and x86_64)
scripts/build-app.sh

# Launch application bundle
open dist/XClose.app
```

Alternatively, open `XClose.xcodeproj` in Xcode and build using the **XClose** scheme.

### First Launch Configuration

1. Launch `XClose.app`.
2. Grant **Accessibility** access under **System Settings > Privacy & Security > Accessibility** (required to identify window close buttons and intercept the click). No other permission is requested.
3. Select **Enable XClose**.

The menu bar icon reflects current operational state:
- **Active:** Interception enabled; standard close button triggers application quit.
- **Dimmed:** Interception paused, starting up, or pending Accessibility permissions.

## Architecture

XClose uses an event-driven interception architecture combining a low-level `CGEvent` tap with macOS Accessibility APIs:

```
Mouse Down -> CGEvent Tap -> Window Server Hit-Test -> Accessibility Validation
                                                             |
                                      +----------------------+----------------------+
                                      |                                             |
                                  Valid Target                                Invalid / Bypass
                                      |                                             |
                              Consume Event                                 Pass Through Event
                                      |                                             |
                              Mouse Up Check                                Standard Window Action
                                      |
                              Dispatch Quit
                     (NSRunningApplication.terminate)
```

1. **Session Event Tap:** Left mouse-down and mouse-up events are inspected via an active `CGEvent` session tap on a dedicated high-priority thread; drag events are only observed while a close-button press is in progress.
2. **Hit-Testing:** The window server identifies the targeted window and process ID without requiring screen capture permissions.
3. **Accessibility Verification:** Queries the hit element's role (`AXButton`), subrole (`AXCloseButton`), and window ownership. Tab close buttons and non-standard controls are disregarded.
4. **Clean Quit Dispatch:** Sends a termination request through `NSRunningApplication.terminate()`. The process handles its own cleanup and document persistence.

Refer to [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full architectural documentation.

## Project Structure

```
XClose/
├── Sources/
│   ├── XCloseCore/             # Platform-independent logic (policy, state, sequence tracking)
│   │   ├── AppIdentity.swift
│   │   ├── ApplicationPolicy.swift
│   │   ├── ClickRules.swift
│   │   ├── ClickSequenceTracker.swift
│   │   ├── OperationalState.swift
│   │   └── QuitRequestTracker.swift
│   └── XClose/                 # macOS application target (AppKit, CGEvent tap, SwiftUI views)
│       ├── XCloseApp.swift
│       ├── MouseEventInterceptor.swift
│       ├── AccessibilityService.swift
│       ├── QuitCoordinator.swift
│       ├── MenuBarController.swift
│       └── Views/
├── Tests/XCloseCoreTests/      # Unit tests for core business logic
├── Resources/                  # Plist manifests, entitlements, and asset catalogs
├── scripts/                    # Build, icon generation, and notarization scripts
├── docs/                       # Architecture, testing, and distribution specifications
└── Package.swift               # Swift package manifest
```

## Testing and Verification

Run the test suite via the command line:

```bash
swift test
```

The test suite covers:
- Close button role, subrole, and ownership verification
- Event sequence transitions (press, drag-to-cancel, release)
- Duplicate request debouncing and process ID validation
- State machine transitions across permission changes and pause states

Detailed verification procedures and manual test matrices are documented in [docs/TESTING.md](docs/TESTING.md).

## Documentation

- [Architecture & Design Details](docs/ARCHITECTURE.md)
- [Testing Matrix & Verification Guide](docs/TESTING.md)
- [Installation, Signing & Distribution](docs/DISTRIBUTION.md)
- [Release Process](docs/RELEASING.md)
- [Changelog](CHANGELOG.md)

## Known Limitations

- **Custom Controls:** Windows with non-native, HTML-rendered, or custom-drawn title bars without standard accessibility semantics are bypassed.
- **Inspectors and Dialogs:** Utility panels, sheets, and modal dialogues retain their standard window-dismissal behavior.
- **Button Visual State:** Because the initial mouse event is consumed to prevent duplicate actions, the button's depressed visual state is not displayed.
- **Unresponsive Processes:** Target processes that do not answer Accessibility queries within 400ms are bypassed and given a cooldown period.

## Contributing

Please review [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on code standards, pull requests, and the testing workflow.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
