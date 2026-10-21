#!/bin/zsh
# Sets the marketing version and bumps the build number everywhere it lives.
#   scripts/set-version.sh 1.1.0
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="${1:?usage: scripts/set-version.sh <version, e.g. 1.1.0>}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Version must look like 1.2.3"; exit 1; }
PLIST=Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $PLIST) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" $PLIST
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" XClose.xcodeproj/project.pbxproj
grep -q "^## $VERSION" CHANGELOG.md || echo "Reminder: add a '## $VERSION' section to CHANGELOG.md"
echo "Version $VERSION (build $BUILD)"
