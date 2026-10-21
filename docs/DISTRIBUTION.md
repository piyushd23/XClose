# Signing, notarization, installation and removal

## Distribution model

XClose ships **directly, signed with a Developer ID and notarized**. It is not on the Mac App Store, for these reasons:

- **The App Sandbox doesn't allow the feature.** A sandboxed app can't be granted Accessibility control over other apps, and can't install a session event tap that blocks events.
- **App Store review rules apply.** The Mac App Store requires the sandbox. Apps whose main function changes other apps' behavior through Accessibility are not accepted.
- **Hardened runtime needs no exceptions.** Accessibility, `CGEvent` taps and `NSRunningApplication.terminate()` all work under the hardened runtime with no exception entitlements. `terminate()` was verified this way. The only entitlement file entry is `app-sandbox = false`.

## Requirements

- macOS 13 Ventura or later. This floor comes from `SMAppService`, `OSAllocatedUnfairLock` and the SwiftUI APIs used.
- The build is universal: Apple Silicon (arm64) and Intel (x86_64).
- To build: Xcode 16 or later, **or** the Command Line Tools with Swift 5.9 or later.
- To distribute: an Apple Developer Program membership with a **Developer ID Application** certificate.

## Build

### Command line (no Xcode required)

```sh
scripts/build-app.sh                  # universal, ad-hoc signed → dist/XClose.app
ARCHS=arm64 scripts/build-app.sh      # one architecture, faster
swift test                            # unit tests
```

### Xcode

1. Open `XClose.xcodeproj`.
2. Select the **XClose** scheme and press Run.
3. For Release, set **Signing › Development Team** on the XClose target.

The Release configuration is already set to use **Developer ID Application**, hardened runtime and secure timestamps.

> The project file was written by hand in an environment without Xcode, so it hasn't been opened in Xcode yet. It uses Xcode 16 folder-synchronized groups. If Xcode reports a problem, `Package.swift` is the reference for targets and settings. You can also open `Package.swift` in Xcode directly for development.

## Developer ID signing and notarization

Credentials are never stored in this repository. Store them once in your keychain:

```sh
xcrun notarytool store-credentials xclose-notary \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

Then run:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=xclose-notary \
scripts/notarize.sh
```

This script:
1. builds the universal app
2. signs it with the hardened runtime and a secure timestamp
3. submits it with `notarytool --wait`
4. staples the ticket
5. validates it with `stapler` and `spctl`
6. writes `dist/XClose-<version>.zip`

To archive in Xcode instead, choose **Product › Archive › Distribute App › Direct Distribution**.

**Status:** neither Developer ID signing nor notarization has been run. No signing identity was available in the build environment. Only ad-hoc signing was verified.

Before shipping, change the bundle identifier `app.xclose.XClose` to one in your own domain. It appears in `Resources/Info.plist` and in the Xcode target settings.

## Installation (end users)

1. Unzip `XClose-<version>.zip` and drag **XClose** into **Applications**.
2. Open XClose and follow the three onboarding steps.
3. When asked, turn on **XClose** in **System Settings › Privacy & Security › Accessibility**. No other permission is needed.
4. Click **Enable XClose**. The menu-bar icon fills in when XClose is Active.
5. Optional: turn on **Settings › General › Launch at login**. If macOS asks for approval, allow it in **System Settings › General › Login Items**.

### XClose doesn't appear in the Accessibility list

macOS registers the app at the location it was running from when access was requested. If XClose was moved afterwards, for example from `dist/` to Applications, that entry can't be resolved and is hidden. To fix it:

1. Quit XClose.
2. Run `tccutil reset Accessibility app.xclose.XClose`.
3. Open XClose from **/Applications**.
4. Click **Grant Access…** again.

You can also click **+** under the Accessibility list and choose `/Applications/XClose.app`. **Settings › Permissions › Show XClose in Finder** helps you find it.

### After an update or rebuild

macOS ties the Accessibility permission to the app's code signature. If XClose shows "Accessibility access required" even though the switch is on, select XClose in the Accessibility list, remove it with **−**, and add it again (or re-enable it).

This happens every time with ad-hoc signed development builds. It shouldn't happen between Developer ID builds signed by the same team.

## Uninstall

1. Choose **Quit XClose** from the menu-bar icon. Normal red × behavior returns immediately.
2. If you turned on Launch at login, turn it off in XClose first, or remove XClose under **System Settings › General › Login Items**.
3. Delete **/Applications/XClose.app**.
4. Optional cleanup:
   - Remove XClose from **System Settings › Privacy & Security › Accessibility**, or run `tccutil reset Accessibility app.xclose.XClose`.
   - Delete preferences with `defaults delete app.xclose.XClose`.

XClose installs nothing else: no helpers, daemons, kernel extensions or files outside its own preferences.
