#!/bin/zsh
# Builds, Developer ID signs, notarizes and staples dist/XClose.app, then
# produces dist/XClose-<version>.zip for distribution.
#
# One-time setup (stores credentials in your login keychain, not in this repo):
#   xcrun notarytool store-credentials xclose-notary \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=xclose-notary scripts/notarize.sh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"
[[ "$SIGN_IDENTITY" == Developer\ ID\ Application* ]] || { echo "SIGN_IDENTITY must be a Developer ID Application identity"; exit 1; }

SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build-app.sh

APP=dist/XClose.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
SUBMISSION=dist/XClose-notary.zip

ditto -c -k --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

rm -f "$SUBMISSION"
ditto -c -k --keepParent "$APP" "dist/XClose-$VERSION.zip"
echo "==> Ready to distribute: dist/XClose-$VERSION.zip"
