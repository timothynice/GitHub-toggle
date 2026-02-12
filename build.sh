#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="GHStatusToggle"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"

fatal() {
  echo "Error: $*" >&2
  exit 1
}

if ! command -v xcrun >/dev/null 2>&1; then
  fatal "xcrun is not available. Install Xcode Command Line Tools: xcode-select --install"
fi

SWIFTC="${SWIFTC:-$(xcrun --find swiftc 2>/dev/null || true)}"
if [[ -z "$SWIFTC" || ! -x "$SWIFTC" ]]; then
  fatal "swiftc was not found. Install Xcode Command Line Tools: xcode-select --install"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK_PATH" || ! -d "$SDK_PATH" ]]; then
  fatal "macOS SDK path could not be resolved."
fi

if [[ ! -f "$ROOT_DIR/Info.plist" ]]; then
  fatal "Info.plist is missing at $ROOT_DIR/Info.plist"
fi

if [[ ! -f "$ROOT_DIR/Sources/main.swift" ]]; then
  fatal "Source file is missing at $ROOT_DIR/Sources/main.swift"
fi

rm -rf "$APP_DIR" "$MODULE_CACHE_DIR"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"
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
echo "Launch: open \"$APP_DIR\""
