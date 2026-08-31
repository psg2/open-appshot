#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
INSTALLED_APP="/Applications/Open AppShot.app"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/OpenAppShot"
TRIGGER="$REPO_ROOT/build/trigger-hotkey"
FIXTURE_BINARY="$REPO_ROOT/build/capture-fixture"

if [[ ! -x "$INSTALLED_BINARY" ]]; then
  echo "Install the app first with: make install" >&2
  exit 1
fi

CAPTURE_ROOT=$("$INSTALLED_BINARY" --capture-root)
mkdir -p "$CAPTURE_ROOT"

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework CoreGraphics \
  "$REPO_ROOT/Tests/Support/TriggerHotkey.swift" \
  -o "$TRIGGER"

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -framework AppKit \
  "$REPO_ROOT/Tests/Fixtures/CaptureFixture.swift" \
  -o "$FIXTURE_BINARY"

if ! pgrep -x OpenAppShot >/dev/null; then
  open -n "$INSTALLED_APP"
fi

for _ in {1..50}; do
  if pgrep -x OpenAppShot >/dev/null; then
    permissions=$("$INSTALLED_BINARY" --permissions-status)
    if [[ "$permissions" == *"accessibility=true"* && "$permissions" == *"screen_recording=true"* ]]; then
      break
    fi
  fi
  sleep 0.2
done

"$FIXTURE_BINARY" &
fixture_pid=$!
cleanup() {
  kill "$fixture_pid" 2>/dev/null || true
  wait "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1

before=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
hotkey_json=$("$INSTALLED_BINARY" --hotkey-json)
hotkey_kind=$(printf '%s' "$hotkey_json" | jq -r '.kind')
trigger_configured_hotkey() {
  if [[ "$hotkey_kind" == "keyboard" ]]; then
    local hotkey_code
    local hotkey_modifiers
    hotkey_code=$(printf '%s' "$hotkey_json" | jq -r '.keyCode')
    hotkey_modifiers=$(printf '%s' "$hotkey_json" | jq -r '.modifierRawValue')
    "$TRIGGER" "$hotkey_code" "$hotkey_modifiers"
  else
    "$TRIGGER"
  fi
}

trigger_configured_hotkey

for attempt in {1..100}; do
  if (( attempt == 25 || attempt == 50 || attempt == 75 )); then
    trigger_configured_hotkey
  fi
  after=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$after" -gt "$before" ]]; then
    latest_capture=$(find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort | tail -1)
    if [[ -f "$latest_capture/context.md" ]]; then
      runtime_host=$(jq -r '.debug_logs[]? | select(contains("Runtime host"))' "$latest_capture/windows.json" | head -1)
      [[ "$runtime_host" == *"local (in-process)"* ]]
      clipboard=$("$INSTALLED_BINARY" --inspect-clipboard)
      [[ "$clipboard" == *"public.png"* ]]
      [[ "$clipboard" == *"public.utf8-plain-text"* ]]
      printf 'capture_directory=%s\n' "$latest_capture"
      printf '%s\n' "$runtime_host"
      printf '%s\n' "$clipboard"
      echo "hotkey_smoke=GREEN attempts=$attempt kind=$hotkey_kind"
      exit 0
    fi
    if [[ -f "$latest_capture/windows.json" ]] && jq -e '.success == false' "$latest_capture/windows.json" >/dev/null 2>&1; then
      jq '{success,error,debug_logs}' "$latest_capture/windows.json" >&2
      exit 1
    fi
  fi
  sleep 0.2
done

echo "Timed out waiting for the global-hotkey capture" >&2
exit 1
