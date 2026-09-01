#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILT_APP="$REPO_ROOT/build/Open AppShot.app"
INSTALLED_APP="/Applications/Open AppShot.app"
LEGACY_INSTALLED_APP="/Applications/AppShot Clipboard POC.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
INSTALL_STAGING_ROOT=""
STAGED_APP=""
BACKUP_APP=""
published_new_app=0
moved_previous_app=0

cleanup() {
  local status=$?
  if [[ "$status" -ne 0 && "$published_new_app" -eq 1 ]]; then
    rm -rf -- "$INSTALLED_APP"
  fi
  if [[ "$status" -ne 0 && "$moved_previous_app" -eq 1 && -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALLED_APP"
  fi
  if [[ -n "$INSTALL_STAGING_ROOT" ]]; then
    rm -rf -- "$INSTALL_STAGING_ROOT"
  fi
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

"$SCRIPT_DIR/build.sh"
pkill -x OpenAppShot 2>/dev/null || true
pkill -x AppShotClipboardPOC 2>/dev/null || true
for _ in {1..100}; do
  if ! pgrep -x OpenAppShot >/dev/null && ! pgrep -x AppShotClipboardPOC >/dev/null; then
    break
  fi
  sleep 0.1
done
if pgrep -x OpenAppShot >/dev/null || pgrep -x AppShotClipboardPOC >/dev/null; then
  echo "Could not stop the existing Open AppShot process" >&2
  exit 1
fi

INSTALL_STAGING_ROOT=$(mktemp -d "/Applications/.open-appshot-install.XXXXXX")
STAGED_APP="$INSTALL_STAGING_ROOT/Open AppShot.app"
BACKUP_APP="$INSTALL_STAGING_ROOT/Previous Open AppShot.app"
ditto "$BUILT_APP" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
if [[ -d "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$BACKUP_APP"
  moved_previous_app=1
fi
mv "$STAGED_APP" "$INSTALLED_APP"
published_new_app=1
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
if [[ -d "$LEGACY_INSTALLED_APP" ]]; then
  "$LSREGISTER" -u "$LEGACY_INSTALLED_APP" >/dev/null 2>&1 || true
fi
"$LSREGISTER" -f "$INSTALLED_APP" >/dev/null 2>&1 || true
/usr/bin/mdimport "$INSTALLED_APP" >/dev/null 2>&1 || true
open -n "$INSTALLED_APP"

# The new app is now verified, registered, and launchable. Disarm rollback
# before removing the backup so a later cleanup failure cannot remove both apps.
published_new_app=0
moved_previous_app=0
if [[ -d "$BACKUP_APP" ]]; then
  rm -rf -- "$BACKUP_APP"
fi
if [[ -d "$LEGACY_INSTALLED_APP" ]]; then
  rm -rf -- "$LEGACY_INSTALLED_APP"
fi

echo "$INSTALLED_APP"
