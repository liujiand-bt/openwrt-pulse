#!/bin/sh
# 生成发布资产：pulse-qwrt.tar.gz（QWRT / 19.07 Lua 版）、openwrt-pulse-modern.tar.gz（router/ + web/）、SHA256SUMS
# 用法：tools/build-release.sh [输出目录]   默认 dist/release
set -e
P=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$P/dist/release}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
"$P/tools/build-qwrt.sh" >/dev/null
cp "$P/dist/pulse-qwrt.tar.gz" "$OUT/pulse-qwrt.tar.gz"
T=$(mktemp -d); M=$T/openwrt-pulse
mkdir -p "$M/router"
cp -r "$P/router/files" "$M/router/"; cp "$P/router/install.sh" "$P/router/uninstall.sh" "$M/router/"
cp -r "$P/web" "$M/web"; cp "$P/LICENSE" "$P/NOTICE.md" "$P/README.md" "$M/"
(cd "$T" && tar --sort=name --owner=0 --group=0 --numeric-owner -czf "$OUT/openwrt-pulse-modern.tar.gz" openwrt-pulse 2>/dev/null \
  || tar czf "$OUT/openwrt-pulse-modern.tar.gz" openwrt-pulse)
rm -rf "$T"
(cd "$OUT" && sha256sum pulse-qwrt.tar.gz openwrt-pulse-modern.tar.gz > SHA256SUMS)
ls -l "$OUT"; cat "$OUT/SHA256SUMS"
