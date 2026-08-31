#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
BUILT_APP="$REPO_ROOT/build/AppShot Clipboard POC.app"
INSTALLED_APP="/Applications/AppShot Clipboard POC.app"

"$SCRIPT_DIR/build.sh"
pkill -x AppShotClipboardPOC 2>/dev/null || true
ditto "$BUILT_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
open -n "$INSTALLED_APP"

echo "$INSTALLED_APP"
