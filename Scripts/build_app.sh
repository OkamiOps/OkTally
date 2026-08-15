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
# Ícone da marca: sem isto o app aparece sem logo no Launchpad e no Finder.
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
# Ad-hoc signatures change identity every build, which invalidates Keychain ACLs and
# forces relogin (Claude/Codex/SuperGrok/API keys) after each update. Prefer a stable
# identity: a local self-signed "OkTally Dev" first, then a real Apple Development
# certificate (present whenever the machine has an Apple Developer account set up).
IDENTITY=""
for CANDIDATE in "OkTally Dev" "Apple Development"; do
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CANDIDATE"; then
    IDENTITY="$CANDIDATE"
    break
  fi
done
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
  echo "Signed with stable identity '$IDENTITY'."
else
  codesign --force --deep --sign - "$APP_BUNDLE"
  cat <<'EOF'
WARNING: ad-hoc signature — Keychain logins will NOT survive rebuilds.
Create a stable identity once with:
  1. Keychain Access > Certificate Assistant > Create a Certificate…
     Name: "OkTally Dev", Identity Type: Self-Signed Root, Certificate Type: Code Signing
  2. Re-run this script.
EOF
fi
echo "Built $APP_BUNDLE"
