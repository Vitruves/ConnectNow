#!/bin/sh
# Regenerate the app icon from its vector source:
#   Resources/Icon/make_svg.py -> Resources/Icon/icon.svg -> Resources/icon.png (1024) + Resources/AppIcon.icns
# Requires python3 and rsvg-convert (brew install librsvg). iconutil ships with macOS.
set -eu
cd "$(dirname "$0")/.."

GEN=Resources/Icon/make_svg.py
SVG=Resources/Icon/icon.svg
PNG=Resources/icon.png
ICNS=Resources/AppIcon.icns

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg" >&2; exit 1; }

python3 "$GEN"
test -f "$SVG" || { echo "$GEN did not produce $SVG" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"

render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"; }

for size in 16 32 64 128 256 512 1024; do
  render "$size" "$TMP/$size.png"
done
for size in 16 32 128 256 512; do
  cp "$TMP/$size.png" "$SET/icon_${size}x${size}.png"
  cp "$TMP/$((size * 2)).png" "$SET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$SET" -o "$ICNS"
cp "$TMP/1024.png" "$PNG"
echo "OK: $PNG, $ICNS"
