#!/bin/sh
# 用无头 Chrome 截图模拟模式。用法：tools/shot.sh [端口]
# 需要先在 web/ 目录起一个静态服务器：python3 -m http.server 8765 --directory web
P=${1:-8765}; OUT=$(dirname "$0")/../screenshots; mkdir -p "$OUT"
CH=${CHROME:-google-chrome}
shot() { # name width height query
  "$CH" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=${4:-1} \
    --window-size=$2,$3 --virtual-time-budget=6000 --screenshot="$OUT/$1.png" \
    "http://127.0.0.1:$P/index.html?mock=1&$5" 2>/dev/null
}
shot desktop-light 1600 1000 1 ""
shot desktop-dark 1600 1000 1 "theme=dark"
shot desktop-en 1600 1000 1 "lang=en"
shot desktop-full 1600 1700 1 ""
shot mobile 390 2600 2 ""
