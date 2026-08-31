#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/build"
APP_PATH="$BUILD_ROOT/Open AppShot.app"
LEGACY_APP_PATH="$BUILD_ROOT/AppShot Clipboard POC.app"

rm -rf "$APP_PATH"
rm -rf "$LEGACY_APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

"$SCRIPT_DIR/build-icon.sh" >/dev/null

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ImageIO \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  "$REPO_ROOT/Sources/OpenAppShot/"*.swift \
  -o "$APP_PATH/Contents/MacOS/OpenAppShot"

cp "$REPO_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$BUILD_ROOT/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.psg2.AppShotClipboardPOC"' \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "$APP_PATH"
