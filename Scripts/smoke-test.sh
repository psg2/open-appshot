#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
APP_PATH="$REPO_ROOT/build/Open AppShot.app"
BINARY="$APP_PATH/Contents/MacOS/OpenAppShot"
FIXTURE_BINARY="$REPO_ROOT/build/capture-fixture"

if [[ ! -x "$BINARY" ]]; then
  "$SCRIPT_DIR/build.sh"
fi

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework AppKit \
  "$REPO_ROOT/Tests/Fixtures/CaptureFixture.swift" \
  -o "$FIXTURE_BINARY"

"$FIXTURE_BINARY" &
fixture_pid=$!
cleanup() {
  kill "$fixture_pid" 2>/dev/null || true
  wait "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT

sleep 1
output=$("$BINARY" --capture-once --pid "$fixture_pid")
capture_directory=$(printf '%s\n' "$output" | sed -n 's/^capture_directory=//p')

[[ "$output" == *"window=Open AppShot Capture Fixture"* ]]
[[ "$output" == *"png_bytes="* ]]
[[ "$output" == *"text_characters="* ]]
[[ -n "$capture_directory" ]]
[[ -s "$capture_directory/screenshot.png" ]]
[[ -s "$capture_directory/thumbnail.png" ]]
[[ -s "$capture_directory/accessibility.json" ]]
[[ -s "$capture_directory/context.md" ]]
[[ -s "$capture_directory/metadata.json" ]]

metadata_application=$(jq -r '.appName' "$capture_directory/metadata.json")
metadata_window=$(jq -r '.windowTitle' "$capture_directory/metadata.json")
metadata_elements=$(jq -r '.elementCount' "$capture_directory/metadata.json")
[[ "$metadata_application" == "capture-fixture" ]]
[[ "$metadata_window" == "Open AppShot Capture Fixture" ]]
[[ "$metadata_elements" -gt 0 ]]

runtime_host=$(jq -r '.debug_logs[]? | select(contains("Runtime host"))' "$capture_directory/windows.json" | head -1)
[[ "$runtime_host" == *"local (in-process)"* ]]

directory_mode=$(stat -f '%Sp' "$capture_directory")
screenshot_mode=$(stat -f '%Sp' "$capture_directory/screenshot.png")
thumbnail_mode=$(stat -f '%Sp' "$capture_directory/thumbnail.png")
metadata_mode=$(stat -f '%Sp' "$capture_directory/metadata.json")
[[ "$directory_mode" == "drwx------" ]]
[[ "$screenshot_mode" == "-rw-------" ]]
[[ "$thumbnail_mode" == "-rw-------" ]]
[[ "$metadata_mode" == "-rw-------" ]]

history_count=$("$BINARY" --history-count)
[[ "$history_count" -gt 0 ]]

clipboard=$("$BINARY" --inspect-clipboard)
[[ "$clipboard" == *"public.png"* ]]
[[ "$clipboard" == *"public.utf8-plain-text"* ]]
[[ "$clipboard" == *"com.psg2.appshot-context-json"* ]]

printf '%s\n' "$output"
printf '%s\n' "$runtime_host"
printf '%s\n' "$clipboard"
printf 'history_count=%s\n' "$history_count"
echo "smoke=GREEN"
