#!/bin/sh
# Renders logo.svg to logo.png (512×512, transparent corners) and the in-game icon Logo64.tga is not
# needed: the addon uses the guild emblem. Needs Chrome and Pillow.
cd "$(dirname "$0")" || exit 1
CHROME=${CHROME:-"/c/Program Files/Google/Chrome/Application/chrome.exe"}
dir="$(pwd -W 2>/dev/null || pwd)"
cat > logo-render.html <<EOF
<!doctype html><html><head><style>html,body{margin:0;width:512px;height:512px;background:transparent}</style></head>
<body><img src="logo.svg" width="512" height="512"></body></html>
EOF
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --default-background-color=00000000 --window-size=512,512 \
  --screenshot="$dir/logo.png" "file:///$dir/logo-render.html" 2>/dev/null
rm -f logo-render.html
python -c "from PIL import Image; im = Image.open('logo.png'); print(im.size, im.mode)"
