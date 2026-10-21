# XClose architecture

XClose makes a window's red × request a normal quit of the app that owns it. This document explains how a click is intercepted, how ownership is decided, and what happens when anything is uncertain.

## Components

| Component | File | Responsibility |
|---|---|---|
| `XCloseCore` (module) | `Sources/XCloseCore/` | Pure logic with no AppKit or Accessibility imports. It covers policy, click rules, click sequencing, quit tracking, state derivation and bounded storage. All of it is unit tested. |
| `MouseEventInterceptor` | `MouseEventInterceptor.swift` | Owns the session `CGEvent` tap on a dedicated thread. Sequences down/drag/up and decides whether each event is passed or swallowed. |
| `ClickInspector` | `ClickInspector.swift` | The per-click decision pipeline. The event tap and the Diagnostics "Test" tool both use it. |
| `AccessibilityService` | `AccessibilityService.swift` | Bounded Accessibility queries that identify a window's own close control. |
| `QuitCoordinator` | `QuitCoordinator.swift` | Sends `NSRunningApplication.terminate()`. Tracks pending requests and confirms termination separately. |
| `ApplicationLifecycleMonitor` | `ApplicationLifecycleMonitor.swift` | Keeps a pid → app snapshot from `NSWorkspace` notifications. Relays wake and session events. |
| `ApplicationPolicyStore` | `ApplicationPolicyStore.swift` | Stores the enable switch, onboarding flag and exclusions in `UserDefaults`. |
| `PermissionManager` | `PermissionManager.swift` | Tracks Accessibility trust live. Shows the system prompt only when the user clicks **Grant Access…**, never automatically. |
| `DiagnosticsStore` | `DiagnosticsStore.swift` | In-memory event log capped at 200 entries, plus counters. |
| `LaunchAtLoginManager` | `LaunchAtLoginManager.swift` | Launch at login via `SMAppService.mainApp`. |
| `AppModel` | `AppModel.swift` | Reconciles everything into one explicit `OperationalState`. |
| `MenuBarController`, `WindowCoordinator`, `Views/` | | Menu-bar UI (AppKit) plus onboarding and settings (SwiftUI). |

## States

`OperationalState.derive(isEnabled:hasAccessibility:tap:)` is a pure function:

| Enabled | Accessibility | Event tap | State | Clicks altered? |
|---|---|---|---|---|
| no | – | – | **Paused** | no (the tap is removed) |
| yes | no | – | **Permission required** | no (the tap is removed) |
| yes | yes | stopped / starting | **Starting** | no |
| yes | yes | running | **Operational** ("Active") | yes |
| yes | yes | failed to start | **Degraded**: unavailable | no |
| yes | yes | repeatedly disabled | **Degraded**: unstable | no (the tap is removed) |

"Active" appears only once the tap has actually been created and enabled. `TapPlanner` decides when to start or stop the tap.

Failed and unstable taps are retried in only four cases:
- once, automatically, 2 s after a failed start (a fresh Accessibility grant can take a moment to propagate)
- when Accessibility is granted
- after wake
- when the user chooses **Try Again**

There is no restart loop.

## How a click is handled

The main tap listens only for `leftMouseDown` and `leftMouseUp`. Trackpad clicks and taps arrive as the same events.

A second tap receives `leftMouseDragged`, but it is enabled **only while a red × press is armed**. The rest of the time XClose is not in the path of any drag on the system (text selection, window moves, and so on). This saves wakeups and keeps drags from waiting on XClose.

### Mouse-down

The pipeline runs in this order and passes the event through at the first doubt:

1. **Precheck.** Each of these passes the event through:
   - XClose is not operational
   - the event is synthetic (it carries XClose's marker, or comes from a private event source)
   - **Option** is held (the documented bypass)
   - any other modifier is held
2. **Window-server hint.** `CGWindowListCopyWindowInfo` (on-screen only) finds the frontmost window under the pointer.
   - Windows above layer 0 count only if they belong to a known regular app.
   - This matters because the Dock owns a transparent full-screen window above all apps. Measured on the development Mac, the call takes about 0.15 ms.
   - The hint gives a candidate owner pid and window bounds. The window list needs no Screen Recording permission: XClose reads only pid, layer, alpha and bounds, never window titles.
3. **Title-bar band.** If the point is more than 80 pt below the window's top edge, pass.
   - This is only a filter that skips Accessibility work for content clicks; it never decides that something *is* a close button.
   - It doesn't check the horizontal position, so right-to-left layouts work.
4. **Policy.** Pass in any of these cases:
   - the candidate app is unknown (the snapshot is refreshed in the background)
   - it is protected, excluded, not a regular app, or XClose itself
   - it timed out on Accessibility within the last 5 s (`PenaltyBox`), so a hung app can't stall clicks
5. **Accessibility verification** (`AccessibilityService`). The system-wide hit test is authoritative: the window server routes it to whichever app really receives the click.
   - `AXUIElementCopyElementAtPosition` returns the element under the point.
   - One `AXUIElementCopyMultipleAttributeValues` call reads role, subrole, enabled, position, size, window and parent.
   - If the hit element is an `AXImage` or `AXUnknown` inside the button, XClose walks up exactly one level.
   - A second batched call reads the window's role, subrole and `kAXCloseButtonAttribute`.
   - `AXUIElementGetPid` gives the owner. It is a local call, not IPC.
   - That's at most 4 IPC calls. Each is capped by a process-wide messaging timeout of 150 ms, and the stage has a 250 ms budget that is checked between calls.
6. **Validation** (`ClickRules.validate`, unit tested). The element must:
   - have role `AXButton` and subrole `AXCloseButton`
   - be `CFEqual` to its window's `kAXCloseButtonAttribute`. This rejects tab close buttons, close buttons in web pages, and "Close" buttons in dialogs.
   - belong to a window with role `AXWindow` and subrole `AXStandardWindow`. Panels, floating windows, dialogs and sheets keep their normal behavior.
   - be enabled. An unknown enabled state counts as uncertain.
   - be owned by the **same pid as the window-server hint**. Ownership comes from the clicked window, never from the frontmost app.
   - contain the point, with 2 pt tolerance.
7. **Arm.** On success the mouse-down is swallowed. `ClickSequenceTracker` stores the pid, app key and button frame. It never keeps an `AXUIElement` across events, so stale elements can't be a problem.

### Mouse-dragged and mouse-up

- While a press is armed, the drag tap is enabled and dragged events are swallowed. It is disabled again on mouse-up, on a new mouse-down, or if macOS disables a tap.
- On mouse-up inside the button frame (with 4 pt tolerance for trackpad jitter), the up is swallowed and a quit request goes to the main thread.
- If the release happens away from the button, the up is still swallowed (the app never saw the down) and nothing happens. This matches how a normal button behaves when you drag off it.
- Because the target app never sees any part of an armed press, its own close action can't run. **Each press produces exactly one outcome: a quit request or nothing.** An unarmed press is never touched.
- A new mouse-down discards any armed press whose mouse-up was lost.

### Quit request

On the main thread, `QuitCoordinator`:
1. re-resolves the pid
2. verifies its bundle id or path still matches what was armed, which guards against pid reuse
3. re-checks policy
4. applies `QuitRequestTracker`. A repeat within 2 s (for example a double-click) is ignored.

It then calls `NSRunningApplication.terminate()`. This sends the app the same request as Quit / ⌘Q, so the app runs its own save prompts and may delay or refuse.

- **Hide while quitting** (on by default, Settings › General). Many apps take a second or more to shut down, and with plain `terminate()` their windows stay on screen meanwhile, so red × felt slow. XClose now hides the app just before requesting the quit, so the windows disappear immediately, as a normal close does. The app's quit flow is unchanged:
  - An `AXObserver` (`AttentionWatch`) watches the hidden app for a new window, a new sheet, or the app unhiding itself. On any of these (for example a save or confirmation prompt), XClose unhides and activates the app at once.
  - If the app is still running 3 s later, it is shown again regardless, so it can never be left hidden.
  - If the app can't be observed, XClose doesn't hide it.
- `terminate()` returning `true` is logged as **Quit requested**, with the time from press to request.
- Termination is confirmed separately, through `NSWorkspace.didTerminateApplicationNotification` for that pid (**Quit confirmed**).
- If the app is still running 30 s later, the request is recorded as **Quit not confirmed** (cancelled, delayed or refused) and dropped. **XClose never retries automatically.** A later click by the user is a new request.

XClose never sends signals, never force-quits and never interacts with dialogs. Helper processes the app leaves behind are not XClose's concern, and are not treated as a failed quit.

## Event-tap callback discipline

- The tap runs on its own thread with its own `CFRunLoop`, at user-interactive QoS. The main thread never sits on the event path.
- For drags, ups and anything that isn't a title-bar mouse-down, the callback does a struct lookup at most.
- Shared state is a value snapshot behind `OSAllocatedUnfairLock`. The main thread publishes it whenever policy, app list or state change. Tracker and penalty state live only on the tap thread.
- Notifications to the UI are fire-and-forget `DispatchQueue.main.async` calls. They are sent only for title-bar clicks that reached Accessibility. Ordinary clicks cost no main-thread work.
- If macOS disables the tap (`tapDisabledByTimeout` or `tapDisabledByUserInput`), it is re-enabled immediately and the tracker is reset. Three timeouts within 60 s mark the tap **unstable**: it is removed and the state becomes Degraded, rather than flapping.

## Failure handling and recovery

| Situation | Behavior |
|---|---|
| Accessibility revoked while running | The `com.apple.accessibility.api` distributed notification or an `apiDisabled` result triggers a recheck. The tap is removed and the state becomes Permission required. |
| Accessibility granted later | Detected through the same notification, through app activation, or with **Recheck**. The tap starts with no relaunch needed (one retry if creation fails at first). |
| Sleep/wake, screens wake, user switches back | The tap is re-enabled if macOS disabled it. A failed or unstable tap gets a fresh attempt. |
| Display changes and scaling | No coordinate cache exists. Event, window-server and Accessibility coordinates all use the same global top-left point space, and points are never converted to pixels. Negative coordinates on secondary displays work. |
| App relaunch or pid reuse | The snapshot updates from launch and terminate notifications. Unknown pids pass through and trigger a refresh. Identity is re-checked before quitting. |
| App hung or slow to answer Accessibility | That click passes through after at most about 400 ms. The app gets a 5 s penalty, during which clicks pass through instantly. |
| XClose paused, quit or crashed | The tap is removed or disabled at once. If XClose crashes, the kernel tears down the tap with the process. Either way, clicks behave normally again immediately. |
| A second XClose instance | It exits at launch, so two taps never fight. |

## Permissions

The only permission is **Accessibility**. This was confirmed on macOS 27.0.1:
- `CGEvent.tapCreate` with `.defaultTap` (which can block events) for mouse events returns `nil` without it.
- A `.listenOnly` mouse tap needs nothing. XClose has to block clicks, so it needs Accessibility.
- XClose doesn't tap keyboard events, so Input Monitoring is not needed.
- `NSRunningApplication.terminate()` from a hardened-runtime binary without the `com.apple.security.automation.apple-events` entitlement delivered the quit without any Automation prompt.

## Why not the alternatives

| Approach | Why it wasn't used |
|---|---|
| Observing `kAXUIElementDestroyedNotification` or window-closed events, then quitting | The window has already closed by then. Close ≠ quit for document apps, and a close can't be told apart from ⌘W. It also violates "never both close and quit". |
| Passing the mouse-down through and only rewriting the mouse-up | The app's button-tracking loop would see a partial click. Moving event locations can move the cursor, and behavior varies by toolkit. |
| Pixel, OCR or fixed-offset detection | Explicitly ruled out. It also breaks with themes, scaling and custom title bars. |
| Code injection or private window-server APIs | Ruled out, and incompatible with SIP and notarization. |
