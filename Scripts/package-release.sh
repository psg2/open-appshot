#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/build"
OUTPUT_DIR="$BUILD_ROOT/release"
mkdir -p "$BUILD_ROOT"
STAGING_DIR=$(mktemp -d "$BUILD_ROOT/open-appshot-release.XXXXXX")
RELEASE_BUILD_ROOT="$STAGING_DIR/build"
APP_PATH="$RELEASE_BUILD_ROOT/Open AppShot.app"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$REPO_ROOT/Resources/Info.plist")
ARCHIVE_NAME="Open-AppShot-$VERSION.zip"
UNSTAPLED_ARCHIVE="$STAGING_DIR/Open-AppShot-$VERSION-notarization.zip"
PUBLISH_DIRECTORY="$STAGING_DIR/release"
STAGED_RELEASE_ARCHIVE="$PUBLISH_DIRECTORY/$ARCHIVE_NAME"
STAGED_CHECKSUM_FILE="$PUBLISH_DIRECTORY/$ARCHIVE_NAME.sha256"
RELEASE_ARCHIVE="$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM_FILE="$OUTPUT_DIR/$ARCHIVE_NAME.sha256"

cleanup() {
  local status=$?
  rm -rf -- "$STAGING_DIR"
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

rm -rf -- "$OUTPUT_DIR"
mkdir -p "$PUBLISH_DIRECTORY"

if [[ -z "${OPEN_APPSHOT_SIGNING_IDENTITY:-}" ]]; then
  echo "Set OPEN_APPSHOT_SIGNING_IDENTITY to a Developer ID Application identity" >&2
  exit 1
fi
if [[ -z "${OPEN_APPSHOT_NOTARY_PROFILE:-}" ]]; then
  echo "Set OPEN_APPSHOT_NOTARY_PROFILE to a notarytool keychain profile" >&2
  exit 1
fi

case "$OPEN_APPSHOT_SIGNING_IDENTITY" in
  Developer\ ID\ Application:*) ;;
  *)
    echo "OPEN_APPSHOT_SIGNING_IDENTITY must be a Developer ID Application identity" >&2
    exit 1
    ;;
esac

OPEN_APPSHOT_ARCHITECTURES="arm64 x86_64" \
  OPEN_APPSHOT_BUILD_ROOT="$RELEASE_BUILD_ROOT" \
  OPEN_APPSHOT_DEPLOYMENT_TARGET="15.0" \
  "$SCRIPT_DIR/build.sh" >/dev/null

ditto -c -k --keepParent "$APP_PATH" "$UNSTAPLED_ARCHIVE"
xcrun notarytool submit "$UNSTAPLED_ARCHIVE" --keychain-profile "$OPEN_APPSHOT_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$STAGED_RELEASE_ARCHIVE"
(
  cd "$PUBLISH_DIRECTORY"
  shasum -a 256 "$ARCHIVE_NAME" >"$(basename "$STAGED_CHECKSUM_FILE")"
)
mv "$PUBLISH_DIRECTORY" "$OUTPUT_DIR"

printf 'archive=%s\n' "$RELEASE_ARCHIVE"
printf 'checksum=%s\n' "$CHECKSUM_FILE"
