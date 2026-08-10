#!/bin/bash
# Scripts/make_dmg.sh — builds the app bundle and packages it as a drag-to-install DMG.
# Usage: bash Scripts/make_dmg.sh [version]   (version defaults to Info.plist's)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
APP_BUNDLE=".build/OkTally.app"
DMG=".build/OkTally-${VERSION}.dmg"
STAGING=".build/dmg-staging"

bash Scripts/build_app.sh

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "OkTally ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGING"
echo "Created $DMG"
