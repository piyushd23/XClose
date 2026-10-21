#!/bin/zsh
# Packages dist/XClose.app (built by build-app.sh) for release:
#   dist/XClose.dmg              drag-to-Applications disk image (download link target)
#   dist/XClose-<version>.zip    Sparkle update archive, EdDSA-signed
#   dist/appcast-item.xml        the <item> to add to site/appcast.xml
#   dist/release-notes.md        this version's CHANGELOG section
#
# SPARKLE_KEY_FILE defaults to ~/.xclose-release/sparkle_ed25519.key.
# Set UPDATE_APPCAST=1 to insert the item into site/appcast.xml as well.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
APP=dist/XClose.app
REPO="${GITHUB_REPOSITORY:-piyushd23/XClose}"
KEY="${SPARKLE_KEY_FILE:-$HOME/.xclose-release/sparkle_ed25519.key}"
[[ -d "$APP" ]] || { echo "Build first: scripts/build-app.sh"; exit 1; }
[[ -f "$KEY" ]] || { echo "Sparkle key not found at $KEY"; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
MIN_OS=$(plist LSMinimumSystemVersion)
ZIP="dist/XClose-$VERSION.zip"
DMG="dist/XClose.dmg"

echo "==> XClose $VERSION ($BUILD)"

# Sparkle archive. ditto keeps symlinks and signatures intact.
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Disk image: the app plus an Applications shortcut.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/XClose.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "XClose $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
SIGN_ID=$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/ && !seen {print $2; seen = 1}')
if [[ "$SIGN_ID" == Developer\ ID* ]]; then codesign --force --sign "$SIGN_ID" --timestamp "$DMG"; fi

# Release notes: the CHANGELOG section for this version.
awk -v v="$VERSION" '
  $0 ~ "^## \\[?" v "\\]?([ ]|$)" { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d' > dist/release-notes.md
[[ -s dist/release-notes.md ]] || { echo "No '## $VERSION' section in CHANGELOG.md"; exit 1; }

# Appcast item. Notes become simple HTML for Sparkle's update window.
SIGNATURE=$(swift scripts/sparkle-keys.swift sign "$ZIP" "$KEY")
LENGTH=$(stat -f %z "$ZIP")
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
NOTES_HTML=$(sed -E -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' \
  -e 's/\*\*([^*]+)\*\*/<b>\1<\/b>/g; s/`([^`]+)`/<code>\1<\/code>/g' \
  -e 's/^### (.*)$/<h3>\1<\/h3>/; s/^[-*] (.*)$/<li>\1<\/li>/' dist/release-notes.md)
cat > dist/appcast-item.xml <<EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$NOTES_HTML
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/XClose-$VERSION.zip"
                 length="$LENGTH" type="application/octet-stream"
                 sparkle:edSignature="$SIGNATURE"/>
    </item>
EOF

if [[ "${UPDATE_APPCAST:-0}" == 1 ]]; then
  python3 -I scripts/update-appcast.py
fi

echo "==> $DMG ($(du -h "$DMG" | cut -f1)), $ZIP ($LENGTH bytes)"
