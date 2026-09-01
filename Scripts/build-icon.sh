#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ICON="$REPO_ROOT/Resources/AppIcon.png"
ICON_BUILD_ROOT="${OPEN_APPSHOT_ICON_BUILD_ROOT:-$REPO_ROOT/build}"
ICONSET_DIR="$ICON_BUILD_ROOT/AppIcon.iconset"
OUTPUT_ICON="$ICON_BUILD_ROOT/AppIcon.icns"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing icon source: $SOURCE_ICON" >&2
  exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

render_icon() {
  local pixels="$1"
  local filename="$2"
  sips -z "$pixels" "$pixels" "$SOURCE_ICON" --out "$ICONSET_DIR/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICON"
rm -rf "$ICONSET_DIR"

echo "$OUTPUT_ICON"
