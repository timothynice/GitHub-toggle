#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Studi0Toggle.app"
BUILD_APP_PATH="$ROOT_DIR/build/$APP_NAME"
INSTALL_BASE="$HOME/Applications"
LAUNCH_AFTER_INSTALL=false

print_help() {
  cat <<'EOF'
Usage:
  ./install.sh [--system] [--launch]

Options:
  --system   Install to /Applications (may require permissions)
  --launch   Launch the app after installing
  --help     Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)
      INSTALL_BASE="/Applications"
      ;;
    --launch)
      LAUNCH_AFTER_INSTALL=true
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_help
      exit 1
      ;;
  esac
  shift
done

"$ROOT_DIR/build.sh"

mkdir -p "$INSTALL_BASE"
DEST_APP_PATH="$INSTALL_BASE/$APP_NAME"
rm -rf "$DEST_APP_PATH"
cp -R "$BUILD_APP_PATH" "$DEST_APP_PATH"

echo "Installed: $DEST_APP_PATH"

if $LAUNCH_AFTER_INSTALL; then
  open "$DEST_APP_PATH"
  echo "Launched: $DEST_APP_PATH"
fi
