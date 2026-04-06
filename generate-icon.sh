#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$ROOT_DIR/Assets"
SOURCE_ARTWORK="${1:-$ASSETS_DIR/Studi0Toggle-icon-source.png}"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
OUTPUT_ICNS="$ASSETS_DIR/AppIcon.icns"
SQUARE_SOURCE="$ASSETS_DIR/AppIcon-square.png"

fatal() {
  echo "Error: $*" >&2
  exit 1
}

if ! command -v sips >/dev/null 2>&1; then
  fatal "sips is not available."
fi

if ! command -v iconutil >/dev/null 2>&1; then
  fatal "iconutil is not available."
fi

if [[ ! -f "$SOURCE_ARTWORK" ]]; then
  fatal "Icon source image not found at $SOURCE_ARTWORK"
fi

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

WIDTH="$(sips -g pixelWidth "$SOURCE_ARTWORK" | awk '/pixelWidth:/{print $2}')"
HEIGHT="$(sips -g pixelHeight "$SOURCE_ARTWORK" | awk '/pixelHeight:/{print $2}')"
if [[ -z "$WIDTH" || -z "$HEIGHT" ]]; then
  fatal "Could not determine source artwork size."
fi

if (( WIDTH < HEIGHT )); then
  CROP_SIZE="$WIDTH"
else
  CROP_SIZE="$HEIGHT"
fi

sips -c "$CROP_SIZE" "$CROP_SIZE" "$SOURCE_ARTWORK" --out "$SQUARE_SOURCE" >/dev/null

render_png() {
  local size="$1"
  local output_path="$2"
  sips -z "$size" "$size" "$SQUARE_SOURCE" --out "$output_path" >/dev/null
}

ICON_FILENAMES=(
  "icon_16x16.png"
  "icon_16x16@2x.png"
  "icon_32x32.png"
  "icon_32x32@2x.png"
  "icon_128x128.png"
  "icon_128x128@2x.png"
  "icon_256x256.png"
  "icon_256x256@2x.png"
  "icon_512x512.png"
  "icon_512x512@2x.png"
)

ICON_SIZES=(
  16
  32
  32
  64
  128
  256
  256
  512
  512
  1024
)

for i in "${!ICON_FILENAMES[@]}"; do
  render_png "${ICON_SIZES[$i]}" "$ICONSET_DIR/${ICON_FILENAMES[$i]}"
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -f "$SQUARE_SOURCE"
echo "Using source artwork: $SOURCE_ARTWORK"
echo "Generated icon set at $ICONSET_DIR"
echo "Generated app icon at $OUTPUT_ICNS"
