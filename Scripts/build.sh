#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${OPEN_APPSHOT_BUILD_ROOT:-$REPO_ROOT/build}"
APP_PATH="$BUILD_ROOT/Open AppShot.app"
LEGACY_APP_PATH="$BUILD_ROOT/AppShot Clipboard POC.app"
DEPLOYMENT_TARGET="${OPEN_APPSHOT_DEPLOYMENT_TARGET:-15.0}"
VERSION="$(tr -d '[:space:]' <"$REPO_ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must contain a semantic version such as 1.2.3" >&2
  exit 1
fi
ARCHITECTURES="${OPEN_APPSHOT_ARCHITECTURES:-arm64 x86_64}"
SIGNING_IDENTITY="${OPEN_APPSHOT_SIGNING_IDENTITY:--}"
mkdir -p "$BUILD_ROOT"
LOCK_DIRECTORY="$BUILD_ROOT/.open-appshot-build.lock"
STAGING_ROOT=""
lock_acquired=0

cleanup() {
  local status=$?
  if [[ -n "$STAGING_ROOT" ]]; then
    rm -rf -- "$STAGING_ROOT"
  fi
  if [[ "$lock_acquired" -eq 1 ]]; then
    rm -rf -- "$LOCK_DIRECTORY"
  fi
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

for _ in {1..600}; do
  if mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
    lock_acquired=1
    printf '%s\n' "$$" >"$LOCK_DIRECTORY/pid"
    break
  fi
  sleep 0.1
done
if [[ "$lock_acquired" -ne 1 ]]; then
  echo "Timed out waiting for another Open AppShot build. Remove $LOCK_DIRECTORY only if no build is running." >&2
  exit 1
fi

STAGING_ROOT=$(mktemp -d "$BUILD_ROOT/open-appshot-build.XXXXXX")
STAGED_APP="$STAGING_ROOT/Open AppShot.app"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

OPEN_APPSHOT_ICON_BUILD_ROOT="$STAGING_ROOT" "$SCRIPT_DIR/build-icon.sh" >/dev/null

thin_binaries=()
for architecture in $ARCHITECTURES; do
  triple="$architecture-apple-macosx$DEPLOYMENT_TARGET"
  # Each architecture keeps its own scratch directory so incremental builds stay valid.
  scratch_path="$REPO_ROOT/.build/release-$architecture"
  swift build \
    --package-path "$REPO_ROOT" \
    --scratch-path "$scratch_path" \
    --configuration release \
    --product OpenAppShot \
    --triple "$triple" >&2
  bin_path=$(swift build \
    --package-path "$REPO_ROOT" \
    --scratch-path "$scratch_path" \
    --configuration release \
    --triple "$triple" \
    --show-bin-path)
  thin_binary="$STAGING_ROOT/OpenAppShot-$architecture"
  cp "$bin_path/OpenAppShot" "$thin_binary"
  thin_binaries+=("$thin_binary")
done

if [[ "${#thin_binaries[@]}" -eq 1 ]]; then
  cp "${thin_binaries[0]}" "$STAGED_APP/Contents/MacOS/OpenAppShot"
else
  xcrun lipo -create "${thin_binaries[@]}" -output "$STAGED_APP/Contents/MacOS/OpenAppShot"
fi

cp "$REPO_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGED_APP/Contents/Info.plist"
cp "$STAGING_ROOT/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
signing_arguments=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  signing_arguments+=(--options runtime --timestamp)
fi
codesign "${signing_arguments[@]}" "$STAGED_APP"

codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
rm -rf -- "$APP_PATH" "$LEGACY_APP_PATH"
mv "$STAGED_APP" "$APP_PATH"
cp "$STAGING_ROOT/AppIcon.icns" "$BUILD_ROOT/AppIcon.icns"

echo "$APP_PATH"
