#!/bin/zsh
# Builds dist/XClose.app with SwiftPM (no Xcode required): universal binary,
# embedded Sparkle.framework, hardened runtime, signed inside-out.
#
#   scripts/build-app.sh                 # universal (arm64 + x86_64)
#   ARCHS=arm64 scripts/build-app.sh     # single architecture, faster
#
# Signing identity, first match wins:
#   SIGN_IDENTITY="Developer ID Application: …"   identity in your keychain (notarizable)
#   SIGNING_P12=path SIGNING_P12_PASSWORD=…       a .p12 file, e.g. the self-signed release identity
#   ~/.xclose-release/signing.p12                 used automatically if present
#   otherwise ad-hoc ("-")
# A stable identity (anything but ad-hoc) keeps users' Accessibility permission
# valid across updates.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
ARCHS=(${=ARCHS:-arm64 x86_64})
CONFIG=release
APP="$ROOT/dist/XClose.app"
SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

[[ -f Resources/Bundle/AppIcon.icns && -f Resources/Bundle/MenuBarIcon.png ]] || swift scripts/make-icon.swift "$ROOT"

binaries=()
for arch in $ARCHS; do
  echo "==> Building $arch"
  swift build -c $CONFIG --product XClose --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch"
  binaries+=("$(swift build -c $CONFIG --product XClose --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch" --show-bin-path)/XClose")
done
[[ -d "$SPARKLE" ]] || SPARKLE=$(find "$ROOT/.build" -path "*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" -maxdepth 8 | head -1)
[[ -d "$SPARKLE" ]] || { echo "Sparkle.framework not found; run 'swift package resolve'"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Bundle/* "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

# Per architecture: load frameworks from the bundle and drop build-machine paths
# (they differ per arch and would leak local directory names), then merge.
EXE="$APP/Contents/MacOS/XClose"
thin=()
for binary in $binaries; do
  copy="$ROOT/.build/XClose-${#thin}.bin"
  cp "$binary" "$copy"
  for rpath in "${(@f)$(otool -l "$copy" | awk '/cmd LC_RPATH/{getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print}')}"; do
    [[ -z "$rpath" || "$rpath" == @* || "$rpath" == /usr/lib/* ]] || install_name_tool -delete_rpath "$rpath" "$copy"
  done
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$copy"
  thin+=("$copy")
done
lipo -create "${thin[@]}" -output "$EXE"
rm -f "${thin[@]}"

# Resolve the signing identity.
KEYCHAIN_ARGS=()
TEMP_KEYCHAIN=""
SAVED_SEARCH_LIST=()
cleanup() {
  if (( ${#SAVED_SEARCH_LIST} )); then security list-keychains -d user -s "${SAVED_SEARCH_LIST[@]}" || true; fi
  if [[ -n "$TEMP_KEYCHAIN" ]]; then security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true; fi
}
trap cleanup EXIT
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIGN_IDENTITY"
  SIGN_ID="$SIGN_IDENTITY"
else
  P12="${SIGNING_P12:-}"
  P12_PASSWORD="${SIGNING_P12_PASSWORD:-}"
  if [[ -z "$P12" && -f "$HOME/.xclose-release/signing.p12" ]]; then
    P12="$HOME/.xclose-release/signing.p12"
    P12_PASSWORD="$(cat "$HOME/.xclose-release/signing.p12.password")"
  fi
  if [[ -n "$P12" ]]; then
    # A throwaway keychain. On CI (GitHub Actions), codesign only finds identities
    # in the search list, so it is added there for the duration of the build and
    # the list is restored afterwards. Locally the user's search list is untouched.
    TEMP_KEYCHAIN="$ROOT/.build/xclose-signing-$$.keychain-db"
    KEYCHAIN_PASSWORD=$(openssl rand -hex 16)
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    security import "$P12" -k "$TEMP_KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-keychain-settings "$TEMP_KEYCHAIN"   # no auto-lock during long builds
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN" >/dev/null 2>&1
    if [[ -n "${CI:-}" ]]; then
      SAVED_SEARCH_LIST=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
      security list-keychains -d user -s "$TEMP_KEYCHAIN" "${SAVED_SEARCH_LIST[@]}"
    fi
    IDENTITY=$(security find-certificate -a "$TEMP_KEYCHAIN" | awk -F'"' '/"labl"/ && !seen {print $4; seen = 1}')
    # Sign by SHA-1 fingerprint: unambiguous, and works for untrusted self-signed certificates.
    SIGN_ID=$(security find-certificate -a -Z "$TEMP_KEYCHAIN" | awk '/^SHA-1 hash:/ && !seen {print $3; seen = 1}')
    [[ -n "$SIGN_ID" ]] || { echo "error: no certificate found in $P12"; exit 1; }
    KEYCHAIN_ARGS=(--keychain "$TEMP_KEYCHAIN")
  else
    IDENTITY="-"
    SIGN_ID="-"
    echo "warning: ad-hoc signing; users would have to re-grant Accessibility after each update"
  fi
fi

echo "==> Signing with: $IDENTITY${SIGN_ID:+ ($SIGN_ID)}"
sign() {
  local args=(--force --options runtime --sign "$SIGN_ID" "${KEYCHAIN_ARGS[@]}")
  if [[ "$IDENTITY" == Developer\ ID* ]]; then args+=(--timestamp); fi
  codesign "${args[@]}" "$@"
}
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
ENTITLEMENTS=Resources/XClose.entitlements
[[ "$IDENTITY" == Developer\ ID* ]] || ENTITLEMENTS=Resources/XClose-unsigned.entitlements
sign --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated
lipo -info "$EXE"
echo "==> Done: $APP"
