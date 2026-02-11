#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="GHStatusToggle"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"

SWIFTC="${SWIFTC:-$(xcrun --find swiftc)}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$MACOS_DIR"
rm -rf "$MODULE_CACHE_DIR"
mkdir -p "$MODULE_CACHE_DIR"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

"$SWIFTC" \
  -O \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework Cocoa \
  "$ROOT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/$APP_NAME"

# Ad-hoc signing avoids launch warnings on newer macOS versions.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built: $APP_DIR"
