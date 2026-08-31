#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
BUILT_APP="$REPO_ROOT/build/Open AppShot.app"
INSTALLED_APP="/Applications/Open AppShot.app"
LEGACY_INSTALLED_APP="/Applications/AppShot Clipboard POC.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$SCRIPT_DIR/build.sh"
pkill -x OpenAppShot 2>/dev/null || true
pkill -x AppShotClipboardPOC 2>/dev/null || true
ditto "$BUILT_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
if [[ -d "$LEGACY_INSTALLED_APP" ]]; then
  "$LSREGISTER" -u "$LEGACY_INSTALLED_APP" >/dev/null 2>&1 || true
  rm -rf "$LEGACY_INSTALLED_APP"
fi
"$LSREGISTER" -f "$INSTALLED_APP" >/dev/null 2>&1 || true
/usr/bin/mdimport "$INSTALLED_APP" >/dev/null 2>&1 || true
open -n "$INSTALLED_APP"

echo "$INSTALLED_APP"
