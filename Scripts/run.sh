#!/bin/bash
set -euo pipefail

# Builds the app and opens it from build/. Extra arguments are passed to the app.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH=$("$SCRIPT_DIR/build.sh" | tail -n 1)
open -n "$APP_PATH" --args "$@"
