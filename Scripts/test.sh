#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/build/Open AppShot.app"
BINARY="$APP_PATH/Contents/MacOS/OpenAppShot"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

"$SCRIPT_DIR/build.sh" >/dev/null

[[ -x "$BINARY" ]]
[[ -s "$APP_PATH/Contents/Resources/AppIcon.icns" ]]
plutil -lint "$INFO_PLIST" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

[[ "$(plutil -extract CFBundleDisplayName raw "$INFO_PLIST")" == "Open AppShot" ]]
[[ "$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")" == "OpenAppShot" ]]
[[ "$(plutil -extract CFBundlePackageType raw "$INFO_PLIST")" == "APPL" ]]
[[ "$(plutil -extract LSUIElement raw "$INFO_PLIST")" == "true" ]]

source_icon_width=$(sips -g pixelWidth "$REPO_ROOT/Resources/AppIcon.png" | awk '/pixelWidth/ { print $2 }')
source_icon_height=$(sips -g pixelHeight "$REPO_ROOT/Resources/AppIcon.png" | awk '/pixelHeight/ { print $2 }')
[[ "$source_icon_width" == "1024" ]]
[[ "$source_icon_height" == "1024" ]]

capture_root=$("$BINARY" --capture-root)
[[ "$capture_root" == /* ]]

history_count=$("$BINARY" --history-count)
[[ "$history_count" =~ ^[0-9]+$ ]]

hotkey_json=$("$BINARY" --hotkey-json)
printf '%s' "$hotkey_json" >"$TEMP_DIR/hotkey.json"
jq empty "$TEMP_DIR/hotkey.json"

permissions=$("$BINARY" --permissions-status)
[[ "$permissions" == *"accessibility="* ]]
[[ "$permissions" == *"screen_recording="* ]]

if "$BINARY" --copy-capture "$TEMP_DIR/missing" --clipboard-mode invalid >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  echo "Invalid clipboard mode unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq "Unknown clipboard mode: invalid" "$TEMP_DIR/stderr"

printf 'bundle=%s\n' "$APP_PATH"
printf 'capture_root=%s\n' "$capture_root"
printf 'cli_contracts=GREEN\n'
printf 'test=GREEN\n'
