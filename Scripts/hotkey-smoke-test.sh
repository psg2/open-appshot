#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLED_APP="/Applications/Open AppShot.app"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/OpenAppShot"
BUILT_APP="$REPO_ROOT/build/Open AppShot.app"
BUILT_BINARY="$BUILT_APP/Contents/MacOS/OpenAppShot"
TRIGGER="$REPO_ROOT/build/trigger-hotkey"
FIXTURE_BINARY="$REPO_ROOT/build/capture-fixture"
latest_capture=""
before_directories=$(mktemp)
current_directories=$(mktemp)

if [[ ! -x "$INSTALLED_BINARY" ]]; then
  echo "Install the app first with: make install" >&2
  exit 1
fi
if [[ ! -x "$BUILT_BINARY" ]] \
  || ! cmp -s "$BUILT_BINARY" "$INSTALLED_BINARY" \
  || ! cmp -s "$BUILT_APP/Contents/Info.plist" "$INSTALLED_APP/Contents/Info.plist"; then
  echo "The installed app does not match the current build. Run: make install" >&2
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

find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort >"$before_directories"

"$FIXTURE_BINARY" --background --activate-for-hotkey &
fixture_pid=$!
# ShellCheck does not treat a function referenced by a trap as invoked.
# shellcheck disable=SC2329
cleanup() {
  kill "$fixture_pid" 2>/dev/null || true
  wait "$fixture_pid" 2>/dev/null || true
  if [[ -n "$latest_capture" && -d "$latest_capture" ]]; then
    case "$latest_capture" in
      "$CAPTURE_ROOT"/*)
        if [[ -f "$latest_capture/metadata.json" ]] \
          && [[ "$(jq -r '.appName // empty' "$latest_capture/metadata.json")" == "capture-fixture" ]] \
          && [[ "$(jq -r '.windowTitle // empty' "$latest_capture/metadata.json")" == "Open AppShot Capture Fixture" ]]; then
          rm -rf -- "$latest_capture"
        fi
        ;;
    esac
  fi
  rm -f "$before_directories" "$current_directories"
}
trap cleanup EXIT
sleep 1

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
  find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort >"$current_directories"
  while IFS= read -r candidate; do
    if [[ -f "$candidate/metadata.json" ]] \
      && [[ "$(jq -r '.appName // empty' "$candidate/metadata.json")" == "capture-fixture" ]] \
      && [[ "$(jq -r '.windowTitle // empty' "$candidate/metadata.json")" == "Open AppShot Capture Fixture" ]]; then
      latest_capture="$candidate"
      break
    fi
  done < <(comm -13 "$before_directories" "$current_directories")

  if [[ -n "$latest_capture" ]]; then
    if [[ -f "$latest_capture/context.md" && -f "$latest_capture/accessibility.json" && -f "$latest_capture/windows.json" ]]; then
      observation_engine=$(jq -r '.data.engine' "$latest_capture/accessibility.json")
      [[ "$observation_engine" == "native" ]]
      runtime_host=$(jq -r '.engine' "$latest_capture/windows.json")
      [[ "$runtime_host" == "native" ]]
      clipboard=$("$INSTALLED_BINARY" --inspect-clipboard)
      [[ "$clipboard" == *"public.png"* ]]
      [[ "$clipboard" == *"public.utf8-plain-text"* ]]
      printf 'capture_directory=%s\n' "$latest_capture"
      printf '%s\n' "$runtime_host"
      printf '%s\n' "$clipboard"
      echo "hotkey_smoke=GREEN attempts=$attempt kind=$hotkey_kind engine=$observation_engine"
      exit 0
    fi
  fi
  sleep 0.2
done

echo "Timed out waiting for the global-hotkey capture" >&2
exit 1
