#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLED_APP="/Applications/Open AppShot.app"
LEGACY_INSTALLED_APP="/Applications/AppShot Clipboard POC.app"
BUILT_BINARY="$REPO_ROOT/build/Open AppShot.app/Contents/MacOS/OpenAppShot"
BUNDLE_IDENTIFIER="com.psg2.AppShotClipboardPOC"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/Support/lsregister"
ROOTS_FILE=$(mktemp)
remove_app=0
remove_data=0
remove_preferences=0
reset_permissions=0
helper_binary=""

cleanup() {
  local status=$?
  rm -f "$ROOTS_FILE"
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: ./Scripts/uninstall-local.sh [options]

  --app                Remove installed application bundles
  --data               Remove app-owned capture roots, excluding arbitrary legacy custom roots
  --preferences        Remove Open AppShot user defaults
  --reset-permissions  Reset Accessibility and Screen Recording grants
  --all                Apply every option above
EOF
}

for argument in "$@"; do
  case "$argument" in
    --app) remove_app=1 ;;
    --data) remove_data=1 ;;
    --preferences) remove_preferences=1 ;;
    --reset-permissions) reset_permissions=1 ;;
    --all)
      remove_app=1
      remove_data=1
      remove_preferences=1
      reset_permissions=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $argument" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$remove_app" -eq 0 && "$remove_data" -eq 0 && "$remove_preferences" -eq 0 && "$reset_permissions" -eq 0 ]]; then
  usage >&2
  exit 2
fi

if [[ "$remove_data" -eq 1 ]]; then
  if [[ -x "$BUILT_BINARY" ]]; then
    helper_binary="$BUILT_BINARY"
  else
    echo "Run 'mise run build' before removing data so ownership can be verified by the current sources" >&2
    exit 1
  fi
  "$helper_binary" --known-capture-roots-nul >"$ROOTS_FILE"
fi

pkill -x OpenAppShot 2>/dev/null || true
pkill -x AppShotClipboardPOC 2>/dev/null || true

if [[ "$remove_data" -eq 1 ]]; then
  while IFS= read -r -d '' capture_root; do
    parent=$(dirname "$capture_root")
    if [[ "$capture_root" != /* || "$(basename "$capture_root")" != "Captures" || "$(basename "$parent")" != "Open AppShot" ]]; then
      echo "Refusing unsafe capture root: $capture_root" >&2
      exit 1
    fi
    if [[ -d "$capture_root" ]]; then
      "$helper_binary" --purge-capture-root "$capture_root"
      rmdir "$capture_root" 2>/dev/null || true
      rmdir "$parent" 2>/dev/null || true
      printf 'purged_data=%s\n' "$capture_root"
    fi
  done <"$ROOTS_FILE"
  if [[ -d /tmp/AppShotClipboardPOC ]]; then
    "$helper_binary" --purge-capture-root /tmp/AppShotClipboardPOC
    rmdir /tmp/AppShotClipboardPOC 2>/dev/null || true
    printf 'purged_data=%s\n' /tmp/AppShotClipboardPOC
  fi
fi

if [[ "$remove_app" -eq 1 ]]; then
  for app_path in "$INSTALLED_APP" "$LEGACY_INSTALLED_APP"; do
    if [[ -d "$app_path" ]]; then
      "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
      rm -rf -- "$app_path"
      printf 'removed_app=%s\n' "$app_path"
    fi
  done
fi

if [[ "$remove_preferences" -eq 1 ]]; then
  defaults delete "$BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
  printf 'removed_preferences=%s\n' "$BUNDLE_IDENTIFIER"
fi

if [[ "$reset_permissions" -eq 1 ]]; then
  tccutil reset Accessibility "$BUNDLE_IDENTIFIER"
  tccutil reset ScreenCapture "$BUNDLE_IDENTIFIER"
  printf 'reset_permissions=%s\n' "$BUNDLE_IDENTIFIER"
fi
