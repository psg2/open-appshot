#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
BUILD_ROOT="$REPO_ROOT/build"
APP_PATH="$BUILD_ROOT/AppShot Clipboard POC.app"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework AppKit \
  -framework ApplicationServices \
  "$REPO_ROOT/Sources/OpenAppShot/main.swift" \
  -o "$APP_PATH/Contents/MacOS/AppShotClipboardPOC"

cp "$REPO_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.psg2.AppShotClipboardPOC"' \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "$APP_PATH"
