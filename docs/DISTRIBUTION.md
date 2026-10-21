# Installation, signing and distribution

## Distribution model

XClose is distributed directly: a DMG on [GitHub Releases](https://github.com/piyushd23/XClose/releases), a landing page at <https://piyushd23.github.io/XClose/>, and Sparkle auto-updates. It is not on the Mac App Store:

- **The App Sandbox doesn't allow the feature.** A sandboxed app can't be granted Accessibility control over other apps, and can't install a session event tap that blocks events.
- **App Store review rules apply.** The Mac App Store requires the sandbox.

### Signing today: a stable self-signed certificate

Releases are not yet signed with an Apple Developer ID or notarized; that requires the paid Apple Developer Program. Instead, every release is signed with the same long-lived **self-signed certificate** (`XClose Self-Signed Release`):

| | Ad-hoc signature | Stable self-signed (current) | Developer ID + notarization (future) |
|---|---|---|---|
| Gatekeeper on first launch | Blocked; "Open Anyway" needed | Blocked; "Open Anyway" needed | Opens normally |
| Accessibility grant survives updates | No (new identity every build) | **Yes** (same designated requirement) | Yes |
| Library validation | Disabled (`XClose-unsigned.entitlements`) | Disabled (`XClose-unsigned.entitlements`) | Enabled (`XClose.entitlements`) |

The designated requirement of a release is `identifier "io.github.piyushd23.XClose" and certificate leaf = H"6faf510a…"`. macOS ties the Accessibility grant to it, so updates keep the permission. This was verified on 2026-10-21: two different builds signed with this certificate had different code hashes and an identical designated requirement.

**Library validation:** the hardened runtime only loads frameworks signed with the app's Apple Team ID. Self-signed certificates have no Team ID, so without `com.apple.security.cs.disable-library-validation` the embedded Sparkle.framework is rejected at launch. This was observed: dyld refused it with "different Team IDs". Developer ID builds use `XClose.entitlements` and keep library validation on.

### Moving to Developer ID later

1. Join the Apple Developer Program and create a **Developer ID Application** certificate. Export it with its private key as a `.p12`.
2. Replace the `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` repository secrets with the Developer ID `.p12`. The build script detects "Developer ID" in the certificate name and switches to secure timestamps and `XClose.entitlements`.
3. Add an App Store Connect API key as `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` and `NOTARY_KEY_P8_BASE64`. The release workflow then notarizes and staples the app and the DMG.
4. Users updating from a self-signed version must grant Accessibility **once more**, because the designated requirement changes. Say so in that release's CHANGELOG entry.

## Requirements

- macOS 13 Ventura or later, on Apple Silicon or Intel (universal binary).
- To build: Xcode 16 or later, **or** the Command Line Tools with Swift 5.9 or later. Network access is needed the first time, to fetch Sparkle.

## Build

```sh
swift test                            # unit tests
scripts/build-app.sh                  # universal → dist/XClose.app
ARCHS=arm64 scripts/build-app.sh      # one architecture, faster
scripts/package-release.sh            # → dist/XClose.dmg, dist/XClose-<version>.zip, appcast item
```

`build-app.sh` picks the signing identity in this order:
1. `SIGN_IDENTITY` (a keychain identity, such as Developer ID)
2. `SIGNING_P12` + `SIGNING_P12_PASSWORD`
3. `~/.xclose-release/signing.p12`
4. ad-hoc

A `.p12` is imported into a throwaway keychain that is deleted afterwards. It is never added to your keychain search list.

In Xcode, open `XClose.xcodeproj` and run the **XClose** scheme. Debug builds are ad-hoc signed and use `XClose-unsigned.entitlements` so Sparkle loads. The project file was written by hand and has not been opened in Xcode yet; `Package.swift` is the reference if Xcode reports a problem.

Publishing releases is described in [RELEASING.md](RELEASING.md).

## Installation (end users)

1. Download [XClose.dmg](https://github.com/piyushd23/XClose/releases/latest/download/XClose.dmg), open it and drag **XClose** into **Applications**.
2. Open XClose. macOS says it can't verify the developer. Open **System Settings › Privacy & Security**, scroll to the message about XClose and click **Open Anyway**, then confirm.
   - Alternatively, in Terminal: `xattr -dr com.apple.quarantine /Applications/XClose.app`
3. Follow the onboarding. Turn on **XClose** in **System Settings › Privacy & Security › Accessibility** when asked. No other permission is needed.
4. Optional: turn on **Settings › General › Launch at login**.

If XClose is opened directly from the disk image, it offers to copy itself to Applications. If macOS runs it from a temporary translocated location (a quarantined copy that wasn't moved), it asks you to move it and quits. The Accessibility grant and updates only work from a stable location.

### Updates

XClose checks `https://piyushd23.github.io/XClose/appcast.xml` once a day (Settings › General › Updates). When an update is found, the menu shows **Update Available**. Sparkle downloads the update, verifies its EdDSA signature against the public key built into the app, and installs it. Updates downloaded by Sparkle are not quarantined, so Gatekeeper doesn't ask again.

### XClose doesn't appear in the Accessibility list

macOS registers the app at the location it was running from when access was requested. If XClose was moved afterwards, that entry can't be resolved and is hidden. To fix it:

1. Quit XClose.
2. Run `tccutil reset Accessibility io.github.piyushd23.XClose`.
3. Open XClose from **/Applications**.
4. Click **Allow…** again.

You can also click **+** under the Accessibility list and choose `/Applications/XClose.app`.

## Uninstall

1. Choose **Quit XClose** from the menu-bar icon. Normal red × behavior returns immediately.
2. If you turned on Launch at login, turn it off in XClose first, or remove XClose under **System Settings › General › Login Items**.
3. Delete **/Applications/XClose.app**.
4. Optional cleanup:
   - `tccutil reset Accessibility io.github.piyushd23.XClose`
   - `defaults delete io.github.piyushd23.XClose`
   - `rm -rf ~/Library/Caches/io.github.piyushd23.XClose` (Sparkle's update cache)

XClose installs nothing else: no helpers, daemons or kernel extensions.
