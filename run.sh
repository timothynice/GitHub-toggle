#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$ROOT_DIR/build/GHStatusToggle.app"

"$ROOT_DIR/build.sh"

open "$APP_PATH"
echo "Running: $APP_PATH"
