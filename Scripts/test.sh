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
[[ "$(plutil -extract LSMinimumSystemVersion raw "$INFO_PLIST")" == "15.0" ]]
version=$(tr -d '[:space:]' <"$REPO_ROOT/VERSION")
[[ "$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")" == "$version" ]]

deployment_target=$(vtool -show-build "$BINARY" | awk '/minos/ { print $2; exit }')
[[ "$deployment_target" == "15.0" ]]
architectures=$(lipo -archs "$BINARY")
[[ "$architectures" == *"arm64"* ]]
[[ "$architectures" == *"x86_64"* ]]

designated_requirement=$(codesign -d -r- "$APP_PATH" 2>&1)
[[ "$designated_requirement" != *'designated => identifier "com.psg2.AppShotClipboardPOC"'* ]]
[[ ! -e "$APP_PATH/Contents/MacOS/capture-fixture" ]]

shared_binary_hash=$(shasum -a 256 "$BINARY" | awk '{ print $1 }')
isolated_build_root="$TEMP_DIR/isolated-build"
OPEN_APPSHOT_ARCHITECTURES="$(uname -m)" \
  OPEN_APPSHOT_BUILD_ROOT="$isolated_build_root" \
  "$SCRIPT_DIR/build.sh" >/dev/null
isolated_app="$isolated_build_root/Open AppShot.app"
codesign --verify --deep --strict "$isolated_app"
[[ -x "$isolated_app/Contents/MacOS/OpenAppShot" ]]
[[ ! -e "$isolated_build_root/.open-appshot-build.lock" ]]
[[ "$(shasum -a 256 "$BINARY" | awk '{ print $1 }')" == "$shared_binary_hash" ]]

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

storage_root="$TEMP_DIR/storage"
managed_old="$storage_root/2020-01-01T00-00-00Z-11111111-1111-4111-8111-111111111111"
managed_recent="$storage_root/2099-01-01T00-00-00Z-22222222-2222-4222-8222-222222222222"
unrelated_old="$storage_root/unrelated-old"
outside_directory="$TEMP_DIR/outside"
mkdir -p "$managed_old" "$managed_recent" "$unrelated_old" "$outside_directory"
printf '{"createdAt":"2020-01-01T00:00:00Z"}\n' >"$managed_old/.open-appshot-capture"
printf '{"createdAt":"2099-01-01T00:00:00Z"}\n' >"$managed_recent/.open-appshot-capture"
printf 'keep\n' >"$unrelated_old/user-file.txt"
printf '{"createdAt":"2020-01-01T00:00:00Z"}\n' >"$unrelated_old/.open-appshot-capture"
printf '{"createdAt":"2020-01-01T00:00:00Z"}\n' >"$outside_directory/.open-appshot-capture"
ln -s "$outside_directory" "$storage_root/symlink-old"

prune_output=$("$BINARY" --prune-captures --storage-root "$storage_root" --retention-days 30)
[[ "$prune_output" == "removed=1" ]]
[[ ! -e "$managed_old" ]]
[[ -d "$managed_recent" ]]
[[ -f "$unrelated_old/user-file.txt" ]]
[[ -f "$outside_directory/.open-appshot-capture" ]]

readonly_legacy="$storage_root/2020-01-01T00-00-00Z-33333333-3333-4333-8333-333333333333"
mkdir -p "$readonly_legacy"
printf '# AppShot context\n' >"$readonly_legacy/context.md"
: >"$readonly_legacy/screenshot.png"
: >"$readonly_legacy/accessibility.json"
[[ "$("$BINARY" --capture-ownership "$readonly_legacy")" == "can_delete=false" ]]
[[ "$("$BINARY" --capture-ownership "$unrelated_old")" == "can_delete=false" ]]

abandoned_staging="$storage_root/.staging-44444444-4444-4444-8444-444444444444"
mkdir -p "$abandoned_staging"
printf '{"createdAt":"2020-01-01T00:00:00Z"}\n' >"$abandoned_staging/.open-appshot-capture"
[[ "$("$BINARY" --prune-captures --storage-root "$storage_root" --retention-days 0)" == "removed=1" ]]
[[ ! -e "$abandoned_staging" ]]

[[ "$("$BINARY" --purge-capture-root "$storage_root")" == "removed=1" ]]
[[ ! -e "$managed_recent" ]]
[[ -f "$unrelated_old/user-file.txt" ]]
[[ -f "$readonly_legacy/context.md" ]]

known_roots=$("$BINARY" --known-capture-roots-nul | tr '\0' '\n')
grep -Fxq "$capture_root" <<<"$known_roots"

mkdir -p "$REPO_ROOT/build/release"
printf 'stale\n' >"$REPO_ROOT/build/release/stale-artifact"
if env -u OPEN_APPSHOT_SIGNING_IDENTITY -u OPEN_APPSHOT_NOTARY_PROFILE -u OPEN_APPSHOT_RELEASE_SIGNING \
  "$SCRIPT_DIR/package-release.sh" >"$TEMP_DIR/package.stdout" 2>"$TEMP_DIR/package.stderr"; then
  echo "Release packaging unexpectedly ran without signing credentials" >&2
  exit 1
fi
grep -Fq 'OPEN_APPSHOT_SIGNING_IDENTITY' "$TEMP_DIR/package.stderr"
[[ ! -e "$REPO_ROOT/build/release/stale-artifact" ]]

env -u OPEN_APPSHOT_SIGNING_IDENTITY -u OPEN_APPSHOT_NOTARY_PROFILE OPEN_APPSHOT_RELEASE_SIGNING=adhoc \
  "$SCRIPT_DIR/package-release.sh" >"$TEMP_DIR/package-adhoc.stdout"
grep -Fxq 'signing=adhoc' "$TEMP_DIR/package-adhoc.stdout"
release_archive="OpenAppShot-$version-macos-universal.zip"
(cd "$REPO_ROOT/build/release" && shasum -a 256 -c "$release_archive.sha256" >/dev/null)
ditto -x -k "$REPO_ROOT/build/release/$release_archive" "$TEMP_DIR/release-app"
release_app="$TEMP_DIR/release-app/Open AppShot.app"
codesign --verify --deep --strict "$release_app"
[[ "$(plutil -extract CFBundleShortVersionString raw "$release_app/Contents/Info.plist")" == "$version" ]]
release_architectures=$(lipo -archs "$release_app/Contents/MacOS/OpenAppShot")
[[ "$release_architectures" == *"arm64"* && "$release_architectures" == *"x86_64"* ]]
"$SCRIPT_DIR/uninstall-local.sh" --help >/dev/null

printf 'bundle=%s\n' "$APP_PATH"
printf 'capture_root=%s\n' "$capture_root"
printf 'deployment_target=%s\n' "$deployment_target"
printf 'architectures=%s\n' "$architectures"
printf 'retention_policy=GREEN\n'
printf 'release_fail_closed=GREEN\n'
printf 'release_adhoc_archive=GREEN\n'
printf 'isolated_release_build=GREEN\n'
printf 'cli_contracts=GREEN\n'
printf 'test=GREEN\n'
