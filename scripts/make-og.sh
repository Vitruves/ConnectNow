#!/bin/sh
# Render scripts/og.html to docs/og.png (1200x630), the image shown when the website is shared.
# Requires Google Chrome and an Internet connection (the font comes from Google Fonts).
set -eu
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
test -x "$CHROME" || { echo "Google Chrome not found (set CHROME=/path/to/chrome)" >&2; exit 1; }

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1200,630 --virtual-time-budget=5000 \
  --screenshot="$PWD/docs/og.png" "file://$PWD/scripts/og.html" 2>/dev/null
echo "OK: docs/og.png"
