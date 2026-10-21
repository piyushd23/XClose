#!/bin/zsh
# Builds dist/XClose.app with SwiftPM (no Xcode required).
#
#   scripts/build-app.sh                 # universal (arm64 + x86_64), ad-hoc signed
#   ARCHS=arm64 scripts/build-app.sh     # single architecture
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh
#
# Ad-hoc signed builds run on this Mac. Distribution needs a Developer ID
# signature and notarization: see docs/DISTRIBUTION.md and scripts/notarize.sh.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
ARCHS=(${=ARCHS:-arm64 x86_64})
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CONFIG=release
APP="$ROOT/dist/XClose.app"

[[ -f Resources/Bundle/AppIcon.icns && -f Resources/Bundle/MenuBarIcon.png ]] || swift scripts/make-icon.swift "$ROOT"

binaries=()
for arch in $ARCHS; do
  echo "==> Building $arch"
  swift build -c $CONFIG --product XClose --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch"
  binaries+=("$(swift build -c $CONFIG --product XClose --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch" --show-bin-path)/XClose")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/XClose"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Bundle/* "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing ($SIGN_IDENTITY) with hardened runtime"
sign_args=(--force --options runtime --entitlements Resources/XClose.entitlements --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && sign_args+=(--timestamp)
codesign "${sign_args[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/XClose"
echo "==> Done: $APP"
