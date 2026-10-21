#!/bin/zsh
# Notarizes and staples an app or disk image. Only meaningful for Developer ID
# signed builds; anything else is skipped with a notice.
#
#   scripts/notarize.sh dist/XClose.app
#   scripts/notarize.sh dist/XClose.dmg
#
# Credentials, either:
#   NOTARY_PROFILE=<name>   from `xcrun notarytool store-credentials` (local use), or
#   NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_KEY_FILE   App Store Connect API key (CI)
set -euo pipefail

TARGET="${1:?usage: scripts/notarize.sh <XClose.app | XClose.dmg>}"
AUTHORITY=$(codesign -dvv "$TARGET" 2>&1 | awk -F= '/^Authority=/ && !seen {print $2; seen = 1}')
if [[ "$AUTHORITY" != Developer\ ID* ]]; then
  echo "Skipping notarization: $TARGET is not Developer ID signed (${AUTHORITY:-unsigned})."
  exit 0
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  CREDENTIALS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -n "${NOTARY_KEY_FILE:-}" ]]; then
  CREDENTIALS=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  echo "Set NOTARY_PROFILE, or NOTARY_KEY_ID + NOTARY_ISSUER_ID + NOTARY_KEY_FILE."
  exit 1
fi

SUBMISSION="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMISSION="$(mktemp -d)/$(basename "$TARGET" .app).zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMISSION"
fi

echo "==> Submitting $TARGET for notarization"
xcrun notarytool submit "$SUBMISSION" "${CREDENTIALS[@]}" --wait
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "==> Notarized and stapled $TARGET"
