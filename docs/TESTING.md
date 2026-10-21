# Testing

## Automated tests

Run them with `swift test`, or in Xcode with the **XCloseCoreTests** target and ⌘U. They use Swift Testing (`import Testing`), which ships with both Xcode 16+ and the Command Line Tools.

**Latest result (2026-10-21, macOS 27.0.1, Swift 6.4, Command Line Tools): 47 tests in 7 suites passed.**

| Suite | What it covers |
|---|---|
| Application policy | Regular apps are eligible. Finder, Dock, SystemUIServer, loginwindow, Control Center and others are always excluded, in any letter case. XClose is excluded by bundle id and by pid. Background and menu-bar apps are excluded. Exclusions use the bundle id case-insensitively, fall back to the path for apps without one, and never match on display name. Apps with no identity are excluded. |
| Click rules | Option-click bypasses. Other modifiers pass through. Inactive and synthetic events pass through. The title-bar band works, including right-to-left layouts and negative coordinates on secondary displays. Content "Close" buttons are rejected, as are close-subrole buttons that aren't the window's own control. Panels, dialogs, floating windows and sheets are rejected, as are disabled or unknown-enabled buttons. The owner must match. The point must be on the button. |
| Click sequencing | Unvalidated presses pass untouched. A validated press and release gives exactly one quit. Dragging away cancels and the up is still swallowed. Trackpad jitter is tolerated. A missed mouse-up is discarded by the next press. Reset works. |
| Quit requests | A double-click sends one request. Termination is confirmed separately from the request. A cancelled quit times out and is never retried automatically. The user can ask again after cancelling. A failed submission leaves nothing pending. Exits of unrelated processes are ignored. |
| Operational state | Paused takes priority. Permission required comes before tap state. Only a running tap is "Active". Only Operational alters clicks. |
| Tap planning and health | The tap starts or stops as state requires, with no flapping after a failure. Three timeouts in 60 s count as unstable, while spread-out timeouts are tolerated. |
| Bounded storage | The log keeps the newest entries within capacity. Penalties expire. |

## Checks performed on the development Mac

Run on 2026-10-21 on macOS 27.0.1, Apple Silicon. The XClose process did **not** have Accessibility permission during these checks.

| Check | Result |
|---|---|
| `swift build` (debug) with no warnings from project sources | ✅ Passed |
| `scripts/build-app.sh` gives a universal `XClose.app` (x86_64 + arm64) | ✅ Passed (`lipo -info`) |
| Hardened runtime and ad-hoc signature verify (`codesign --verify --strict`) | ✅ Passed (`flags=0x10002(adhoc,runtime)`) |
| Info.plist, entitlements and `project.pbxproj` parse (`plutil -lint`), and every pbxproj object reference resolves | ✅ Passed |
| An active (event-blocking) mouse `CGEvent` tap can't be created without Accessibility; a listen-only one can | ✅ Confirmed |
| `CGWindowListCopyWindowInfo` gives pid, layer and bounds without Screen Recording, and window names are hidden. It takes about 0.15 ms per call. | ✅ Confirmed |
| The Dock owns a full-screen layer-20 window above app windows, which is why the hint skips it | ✅ Observed |
| `NSRunningApplication.terminate()` from a hardened-runtime binary with no Apple Events entitlement quits Calculator, with no Automation prompt | ✅ Passed (request returned `true`; exit confirmed within 0.1 s) |
| `XClose.app` launches, shows onboarding, has no crash reports, and quits normally through `terminate()` | ✅ Passed |
| Opening the project in Xcode | ⛔ Not run: Xcode is not installed in the build environment |
| Real red × interception (Accessibility hit test plus swallowing the click) | ⛔ Not run: needs Accessibility granted and physical clicks (see below) |

## Manual compatibility matrix

These need a Mac where XClose has Accessibility permission and someone clicks with a real mouse or trackpad. **None of these have been run yet.** Record each result as Pass, Fail or N/A, with notes.

Before each session:
1. Build and install the app in `/Applications`.
2. Grant Accessibility.
3. Open **Settings › Diagnostics**.

To check an app without quitting it, use **Diagnostics › Test**: hover over its red × and read the verdict. When testing for real, check Diagnostics for **Quit requested**, then **Quit confirmed** or **Quit not confirmed**. A request is not proof that the app exited.

| # | Scenario | Expected | Result |
|---|---|---|---|
| 1 | Safari, 3 windows with several tabs: click red × on a background window | Safari quits (all windows). Its own "Close tabs?" / quit confirmation appears if enabled. | Not yet run |
| 2 | Safari: click a tab's × | The tab closes normally (`notWindowCloseButton`) | Not yet run |
| 3 | Chrome, 2 windows: red × | Chrome quits. Its "Warn before quitting" behavior is respected. | Not yet run |
| 4 | TextEdit with an unsaved document: red × | The save sheet or quit review appears. Cancel → TextEdit stays running and usable, and Diagnostics later shows "Quit not confirmed". | Not yet run |
| 5 | TextEdit: Option-click red × | Only that window closes (the normal save prompt) | Not yet run |
| 6 | TextEdit: ⌘W, yellow, green | Unchanged | Not yet run |
| 7 | VS Code (Electron): red × | VS Code quits, with its own dirty-file prompt | Not yet run |
| 8 | Another Electron app (Slack, Discord or Obsidian): red × | The app quits. (Slack may stay in the menu bar per its own settings. That's the app's choice.) | Not yet run |
| 9 | Finder window: red × | The window closes normally (protected) | Not yet run |
| 10 | App with custom window controls (for example a frameless Electron app with HTML buttons) | Normal behavior. Diagnostics shows "Not a close button". | Not yet run |
| 11 | Catalyst app (for example Messages or Podcasts): red × | Quits | Not yet run |
| 12 | Java app with native window frame (for example a JetBrains IDE): red × | Quits | Not yet run |
| 13 | Second display (left of, or above, the main display): red × | Quits (checks negative coordinates) | Not yet run |
| 14 | Full-screen window: reveal the title bar, click red × | Quits, or passes through (record which) | Not yet run |
| 15 | Mixed-DPI displays (Retina plus a non-Retina external) | Detection works on both | Not yet run |
| 16 | Click red × of an inactive (background) window | The window's owner quits, not the frontmost app | Not yet run |
| 17 | Press red ×, drag away, release | Nothing happens. Diagnostics shows "Released outside". | Not yet run |
| 18 | Double-click red × | One quit request. Diagnostics shows "Duplicate ignored". | Not yet run |
| 19 | Web page with a "Close" button, and a dialog with a Close button | Normal behavior | Not yet run |
| 20 | Settings or Inspector panel (floating), and a sheet | Normal behavior (`notStandardWindow`) | Not yet run |
| 21 | Unresponsive app (for example `kill -STOP <pid>` on a test app, then click its red ×; afterwards `kill -CONT`) | The click passes through after ≤ about 0.4 s. Further clicks pass instantly for 5 s. The tap is not disabled. | Not yet run |
| 22 | Permission denied at onboarding | The state shows "Accessibility access required". Nothing is intercepted, and there are no repeated prompts. | Not yet run |
| 23 | Revoke Accessibility while Active | The state drops to "Permission required" within a few seconds. Clicks are normal. | Not yet run |
| 24 | Grant Accessibility while running | The state becomes "Active" with no relaunch | Not yet run |
| 25 | Sleep, then wake, then red × | Still works. Diagnostics shows no unstable state. | Not yet run |
| 26 | Pause from the menu bar, then red × | The window closes normally | Not yet run |
| 27 | Exclude an app, then red × | The window closes normally | Not yet run |
| 28 | Running alongside Mos (or LinearMouse, BetterTouchTool) | Both keep working | Not yet run |
| 29 | Launch at login: enable, log out, log in | XClose starts and becomes Active | Not yet run |
| 30 | Quit XClose, then red × | Normal close behavior | Not yet run |
| 31 | Hide while quitting: red × on Chrome or VS Code | Windows vanish immediately. The app exits in the background. Diagnostics shows "Quit requested (… ms after press, hidden)" and then "Quit confirmed". | Not yet run |
| 32 | Hide while quitting: red × on TextEdit with unsaved changes | TextEdit vanishes, then reappears in front with its save prompt. Diagnostics shows "Shown again: it needs your attention". Cancel → it stays running and visible. | Not yet run |
| 33 | Drag text or windows for a while with XClose Active | Feels the same as with XClose paused. The drag tap is off unless a red × press is armed. | Not yet run |

Record how long detection takes (Diagnostics › Slowest detection) for a typical session. The expected order of magnitude is a few milliseconds.

## Release checklist

Run these against the published DMG before announcing a release. Ideally use a Mac or user account that has never run XClose. **None have been run yet** for 1.0.0.

| # | Check | Expected | Result |
|---|---|---|---|
| R1 | Download from the website and open the DMG | The window shows XClose and an Applications shortcut | Not yet run |
| R2 | Open XClose straight from the DMG | Offers to copy itself to Applications, then relaunches from there | Not yet run |
| R3 | First launch from Applications | macOS blocks it; **Open Anyway** in Privacy & Security opens it. The onboarding appears. | Not yet run |
| R4 | Grant Accessibility during onboarding | Status becomes Active with no relaunch, and red × quits an app | Not yet run |
| R5 | Menu-bar icon and Settings | The star-on-tile icon is visible. Every Settings pane opens. | Not yet run |
| R6 | Update from the previous version (**Check for Updates…**) | Update window with release notes. Installs, relaunches, and is still **Active** with no new Accessibility prompt. | Not yet run (needs a second release) |
| R7 | Scheduled update check | Within a day, "Update Available" appears in the menu without a window popping up | Not yet run (needs a second release) |
| R8 | Turn off automatic update checks, quit, relaunch | The setting stays off | Not yet run |
| R9 | Website on a phone | Readable, no horizontal scrolling, download link works | Rendered check only (390 pt width, WebKit) |

Checks performed while preparing 1.0.0, on the development Mac (2026-10-21):

| Check | Result |
|---|---|
| Two builds signed with the release certificate have different code hashes and the same designated requirement | ✅ Passed |
| A hardened-runtime build without the library-validation exception crashes at launch: dyld rejects Sparkle ("different Team IDs") | ✅ Observed, which is why `XClose-unsigned.entitlements` exists |
| With `XClose-unsigned.entitlements`, the app launches and Sparkle.framework is loaded (`vmmap`) | ✅ Passed |
| The release zip's EdDSA signature is accepted by Sparkle 2.10.0's own `sign_update --verify` | ✅ Passed |
| CryptoKit and Sparkle key formats are interchangeable, checked in both directions | ✅ Passed |
| The app inside the mounted DMG passes `codesign --verify --deep --strict` | ✅ Passed |
| The appcast stays well-formed after inserting an item, and duplicate versions are refused | ✅ Passed (`xmllint`) |
| The release binary contains no build-machine paths | ✅ Passed |
| GitHub Actions workflows | ⛔ Not run: they need the repository secrets, then a pushed tag |
| End-to-end Sparkle update | ⛔ Not run: needs two published releases |
