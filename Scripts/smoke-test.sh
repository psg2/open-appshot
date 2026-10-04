#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/build/Open AppShot.app"
BINARY="$APP_PATH/Contents/MacOS/OpenAppShot"
ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
FIXTURE_BINARY="$REPO_ROOT/build/capture-fixture"
IMAGE_INSPECTOR="$REPO_ROOT/build/inspect-image"
capture_directory=""
no_window_fixture_pid=""
ambiguous_fixture_pid=""

if [[ ! -x "$BINARY" || ! -s "$ICON" ]]; then
  "$SCRIPT_DIR/build.sh"
fi
CAPTURE_ROOT=$("$BINARY" --capture-root)

[[ -s "$ICON" ]]
icon_file=$(plutil -extract CFBundleIconFile raw "$APP_PATH/Contents/Info.plist")
[[ "$icon_file" == "AppIcon.icns" ]]

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework AppKit \
  "$REPO_ROOT/Tests/Fixtures/CaptureFixture.swift" \
  -o "$FIXTURE_BINARY"

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework CoreGraphics \
  -framework ImageIO \
  "$REPO_ROOT/Tests/Support/InspectImage.swift" \
  -o "$IMAGE_INSPECTOR"

"$FIXTURE_BINARY" --background &
fixture_pid=$!
cleanup() {
  kill "$fixture_pid" 2>/dev/null || true
  wait "$fixture_pid" 2>/dev/null || true
  if [[ -n "$no_window_fixture_pid" ]]; then
    kill "$no_window_fixture_pid" 2>/dev/null || true
    wait "$no_window_fixture_pid" 2>/dev/null || true
  fi
  if [[ -n "$ambiguous_fixture_pid" ]]; then
    kill "$ambiguous_fixture_pid" 2>/dev/null || true
    wait "$ambiguous_fixture_pid" 2>/dev/null || true
  fi
  if [[ -n "$capture_directory" && -d "$capture_directory" ]]; then
    case "$capture_directory" in
      "$CAPTURE_ROOT"/*)
        if [[ -f "$capture_directory/metadata.json" ]] \
          && [[ "$(jq -r '.appName // empty' "$capture_directory/metadata.json")" == "capture-fixture" ]] \
          && [[ "$(jq -r '.windowTitle // empty' "$capture_directory/metadata.json")" == "Open AppShot Capture Fixture" ]]; then
          rm -rf -- "$capture_directory"
        fi
        ;;
    esac
  fi
}
trap cleanup EXIT

assert_clipboard_shape() {
  local output="$1"
  local expects_png="$2"
  local expects_text="$3"
  local expects_context="$4"
  local png_bytes
  local text_characters
  local context_bytes
  png_bytes=$(printf '%s\n' "$output" | sed -n 's/^png_bytes=//p' | tail -1)
  text_characters=$(printf '%s\n' "$output" | sed -n 's/^text_characters=//p' | tail -1)
  context_bytes=$(printf '%s\n' "$output" | sed -n 's/^context_json_bytes=//p' | tail -1)

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

image_metrics=$("$IMAGE_INSPECTOR" "$capture_directory/screenshot.png")
opaque_fraction=$(printf '%s\n' "$image_metrics" | sed -n 's/^opaque_fraction=//p')
opaque_width_coverage=$(printf '%s\n' "$image_metrics" | sed -n 's/^opaque_width_coverage=//p')
opaque_height_coverage=$(printf '%s\n' "$image_metrics" | sed -n 's/^opaque_height_coverage=//p')
awk -v value="$opaque_fraction" 'BEGIN { exit !(value >= 0.90) }'
awk -v value="$opaque_width_coverage" 'BEGIN { exit !(value >= 0.99) }'
awk -v value="$opaque_height_coverage" 'BEGIN { exit !(value >= 0.99) }'

metadata_application=$(jq -r '.appName' "$capture_directory/metadata.json")
metadata_window=$(jq -r '.windowTitle' "$capture_directory/metadata.json")
metadata_elements=$(jq -r '.elementCount' "$capture_directory/metadata.json")
[[ "$metadata_application" == "capture-fixture" ]]
[[ "$metadata_window" == "Open AppShot Capture Fixture" ]]
[[ "$metadata_elements" -gt 0 ]]

directory_mode=$(stat -f '%Sp' "$capture_directory")
screenshot_mode=$(stat -f '%Sp' "$capture_directory/screenshot.png")
thumbnail_mode=$(stat -f '%Sp' "$capture_directory/thumbnail.png")
metadata_mode=$(stat -f '%Sp' "$capture_directory/metadata.json")
marker_mode=$(stat -f '%Sp' "$capture_directory/.open-appshot-capture")
[[ "$directory_mode" == "drwx------" ]]
[[ "$screenshot_mode" == "-rw-------" ]]
[[ "$thumbnail_mode" == "-rw-------" ]]
[[ "$metadata_mode" == "-rw-------" ]]
[[ "$marker_mode" == "-rw-------" ]]

"$FIXTURE_BINARY" --background --no-window &
no_window_fixture_pid=$!
sleep 1
before_failed_capture=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -print | sort)
if "$BINARY" --capture-once --pid "$no_window_fixture_pid" --clipboard-mode full >/dev/null 2>&1; then
  echo "Capture unexpectedly succeeded for a fixture without windows" >&2
  exit 1
fi
after_failed_capture=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -print | sort)
[[ "$before_failed_capture" == "$after_failed_capture" ]]
[[ -z "$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -name '.staging-*' -print -quit)" ]]

"$FIXTURE_BINARY" --background --ambiguous-windows &
ambiguous_fixture_pid=$!
sleep 1
before_ambiguous_capture=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -print | sort)
if "$BINARY" --capture-once --pid "$ambiguous_fixture_pid" --clipboard-mode full \
  >"$REPO_ROOT/build/ambiguous.stdout" 2>"$REPO_ROOT/build/ambiguous.stderr"; then
  echo "Capture unexpectedly selected one of two indistinguishable windows" >&2
  exit 1
fi
grep -Fq 'could not identify one active window' "$REPO_ROOT/build/ambiguous.stderr"
after_ambiguous_capture=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -print | sort)
[[ "$before_ambiguous_capture" == "$after_ambiguous_capture" ]]
[[ -z "$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -name '.staging-*' -print -quit)" ]]

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

printf '%s\n' "$output" "$image_metrics"
echo "smoke=GREEN"
