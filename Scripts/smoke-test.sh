#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
APP_PATH="$REPO_ROOT/build/Open AppShot.app"
BINARY="$APP_PATH/Contents/MacOS/OpenAppShot"
ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
FIXTURE_BINARY="$REPO_ROOT/build/capture-fixture"

if [[ ! -x "$BINARY" || ! -s "$ICON" ]]; then
  "$SCRIPT_DIR/build.sh"
fi

[[ -s "$ICON" ]]
icon_file=$(plutil -extract CFBundleIconFile raw "$APP_PATH/Contents/Info.plist")
[[ "$icon_file" == "AppIcon.icns" ]]

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

assert_clipboard_shape() {
  local output="$1"
  local expects_png="$2"
  local expects_text="$3"
  local expects_context="$4"
  local png_bytes=$(printf '%s\n' "$output" | sed -n 's/^png_bytes=//p' | tail -1)
  local text_characters=$(printf '%s\n' "$output" | sed -n 's/^text_characters=//p' | tail -1)
  local context_bytes=$(printf '%s\n' "$output" | sed -n 's/^context_json_bytes=//p' | tail -1)

  if [[ "$expects_png" == "yes" ]]; then [[ "$png_bytes" -gt 0 ]]; else [[ "$png_bytes" -eq 0 ]]; fi
  if [[ "$expects_text" == "yes" ]]; then [[ "$text_characters" -gt 0 ]]; else [[ "$text_characters" -eq 0 ]]; fi
  if [[ "$expects_context" == "yes" ]]; then [[ "$context_bytes" -gt 0 ]]; else [[ "$context_bytes" -eq 0 ]]; fi
}

sleep 1
output=$("$BINARY" --capture-once --pid "$fixture_pid" --clipboard-mode full)
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

full_clipboard=$("$BINARY" --copy-capture "$capture_directory" --clipboard-mode full)
assert_clipboard_shape "$full_clipboard" yes yes yes

references_clipboard=$("$BINARY" --copy-capture "$capture_directory" --clipboard-mode references)
assert_clipboard_shape "$references_clipboard" yes yes no
reference_text=$("$BINARY" --clipboard-text)
[[ "$reference_text" == *"Accessibility JSON: $capture_directory/accessibility.json"* ]]
[[ "$reference_text" == *"Readable context: $capture_directory/context.md"* ]]
[[ "$reference_text" != *"## Accessibility summary"* ]]

image_clipboard=$("$BINARY" --copy-capture "$capture_directory" --clipboard-mode image)
assert_clipboard_shape "$image_clipboard" yes no no

accessibility_clipboard=$("$BINARY" --copy-capture "$capture_directory" --clipboard-mode accessibility)
assert_clipboard_shape "$accessibility_clipboard" no yes yes

clipboard=$("$BINARY" --copy-capture "$capture_directory" --clipboard-mode full)
assert_clipboard_shape "$clipboard" yes yes yes

printf '%s\n' "$output"
printf '%s\n' "$runtime_host"
printf '%s\n' "$clipboard"
printf 'clipboard_modes=full,references,image,accessibility\n'
printf 'history_count=%s\n' "$history_count"
printf 'icon=%s\n' "$icon_file"
echo "smoke=GREEN"
