#!/bin/sh
# Renders every gallery page (*.html) to a 1920×1080 JPG next to it (quality 90, no chroma subsampling:
# a third of the PNG size without visible loss). Needs fonts/FRIZQT__.TTF (see README.md), Chrome and Pillow.
cd "$(dirname "$0")" || exit 1
CHROME=${CHROME:-"/c/Program Files/Google/Chrome/Application/chrome.exe"}
for page in ${1:-*.html}; do
  out="$(pwd -W 2>/dev/null || pwd)/${page%.html}.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1920,1080 --virtual-time-budget=5000 \
    --screenshot="$out" "file:///$(pwd -W 2>/dev/null || pwd)/$page" 2>/dev/null
  python -c "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('RGB').save(sys.argv[2], quality=90, optimize=True, progressive=True, subsampling=0)" "$out" "${out%.png}.jpg" && rm "$out"
  echo "${out%.png}.jpg"
done
