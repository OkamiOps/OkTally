#!/bin/bash
# Scripts/build_app.sh
set -euo pipefail
swift build -c release
APP_NAME="OkTally"
BUILD_DIR=".build/release"
APP_BUNDLE=".build/${APP_NAME}.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$APP_BUNDLE"
echo "Built $APP_BUNDLE"
