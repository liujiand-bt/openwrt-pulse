#!/bin/sh
# 打包给 QWRT / OpenWrt 19.07 用的安装包：dist/pulse-qwrt.tar.gz
# 采集器去掉整行注释和缩进以节省闪存；前端原样附带（只在 tmp 模式或电脑上使用）
set -e
P=$(cd "$(dirname "$0")/.." && pwd); D=$P/dist/pulse-qwrt; F=$P/router19/files
rm -rf "$P/dist"; mkdir -p "$D"
{ head -1 "$F/www/cgi-bin/pulse"; sed '1d' "$F/www/cgi-bin/pulse" | sed -e 's/^[[:space:]]*//' -e '/^--/d' -e '/^$/d'; } > "$D/pulse"
cp "$F/usr/share/pulse/diag.sh" "$F/usr/share/pulse/server.sh" "$D/"
cp "$F/etc/config/pulse" "$D/pulse.config"; cp "$F/etc/sysctl.d/99-pulse.conf" "$D/"
cp "$P/router19/install.sh" "$P/router19/uninstall.sh" "$D/"
cp -r "$P/web" "$D/web"; cp "$P/LICENSE" "$P/NOTICE.md" "$P/router19/INSTALL-QWRT.md" "$D/"
chmod 755 "$D"/*.sh "$D/pulse"
(cd "$P/dist" && tar czf pulse-qwrt.tar.gz pulse-qwrt)
lua5.1 -e "assert(loadfile('$D/pulse'))" 2>/dev/null || luac5.1 -p "$D/pulse"
echo "dist/pulse-qwrt.tar.gz  $(wc -c < "$P/dist/pulse-qwrt.tar.gz") 字节"
echo "写入闪存的文件（常驻安装）:"; wc -c "$D/pulse" "$D/diag.sh" "$D/server.sh" "$D/pulse.config" "$D/99-pulse.conf"
