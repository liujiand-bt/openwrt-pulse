#!/bin/sh
# openwrt-pulse 安装脚本 · QWRT / OpenWrt 19.07（Lua 采集器，无需 ucode）
#   sh install.sh          常驻安装：采集器 + 配置写入闪存（约 30 KB），前端在电脑上打开
#   sh install.sh tmp      临时安装：全部放在 /tmp（内存），附带前端，在 :8088 起一个小网站；重启后消失
HERE=$(cd "$(dirname "$0")" && pwd)
MODE=${1:-persist}
die() { echo "错误: $*"; exit 1; }
command -v lua >/dev/null 2>&1 || die "没有 lua，无法运行采集器。请运行 sh $HERE/diag.sh 并把结果发给我们"
lua -e "assert(loadfile('$HERE/pulse'))" || die "采集器脚本语法检查失败"
LANIP=$(uci -q get network.lan.ipaddr | cut -d/ -f1); [ -n "$LANIP" ] || LANIP=192.168.1.1
TOKEN=$(head -c 12 /dev/urandom | md5sum | cut -c1-16)

echo "[1] 打开 conntrack 字节统计（ECM 硬件加速会把字节数回写到 conntrack）"
sysctl -w net.netfilter.nf_conntrack_acct=1 >/dev/null 2>&1 || echo 1 > /proc/sys/net/netfilter/nf_conntrack_acct
echo "    当前 nf_conntrack_acct=$(cat /proc/sys/net/netfilter/nf_conntrack_acct)；只对之后新建的连接生效，建议装完重启一次路由器"

if [ "$MODE" = tmp ]; then
	echo "[2] 复制到 /tmp/pulse（不占闪存）"
	mkdir -p /tmp/pulse/www/cgi-bin
	cp "$HERE/pulse" /tmp/pulse/www/cgi-bin/pulse && chmod 755 /tmp/pulse/www/cgi-bin/pulse
	cp "$HERE/diag.sh" "$HERE/server.sh" /tmp/pulse/
	[ -d "$HERE/web" ] && cp -r "$HERE/web/." /tmp/pulse/www/
	if [ -f /etc/config/pulse ]; then
		TOKEN=$(uci -q get pulse.main.token)
	else
		printf 'token=%s\ncors_origin=*\ncounters=auto\n' "$TOKEN" > /tmp/pulse/pulse.conf
	fi
	sh /tmp/pulse/server.sh start || exit 1
	echo
	echo "测试采集器: curl -s 'http://$LANIP:8088/cgi-bin/pulse?token=$TOKEN' | head -c 300"
	echo "打开面板:   http://$LANIP:8088/?endpoint=/cgi-bin/pulse&token=$TOKEN"
	echo "停止:       sh /tmp/pulse/server.sh stop      （重启路由器也会全部消失）"
	exit 0
fi

FREE=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
[ -n "$FREE" ] && [ "$FREE" -lt 80 ] && die "overlay 只剩 ${FREE} KB，空间不够，建议用 sh install.sh tmp"
echo "[2] 安装采集器与配置（overlay 剩余 ${FREE:-?} KB）"
cp "$HERE/pulse" /www/cgi-bin/pulse && chmod 755 /www/cgi-bin/pulse || die "无法写入 /www/cgi-bin"
mkdir -p /usr/share/pulse && cp "$HERE/diag.sh" "$HERE/server.sh" /usr/share/pulse/
mkdir -p /etc/sysctl.d && cp "$HERE/99-pulse.conf" /etc/sysctl.d/99-pulse.conf
if [ -f /etc/config/pulse ]; then
	TOKEN=$(uci -q get pulse.main.token); echo "    保留已有 /etc/config/pulse"
else
	cp "$HERE/pulse.config" /etc/config/pulse && chmod 600 /etc/config/pulse
	uci set pulse.main.token="$TOKEN" && uci commit pulse
fi
rm -rf /tmp/pulse/last.json
echo "[3] 自检"
OUT=$(QUERY_STRING="token=$TOKEN" REQUEST_METHOD=GET lua /www/cgi-bin/pulse 2>&1 | sed '1,/^\r*$/d')
echo "$OUT" | grep -q '"collector":"lua"' && echo "    采集器 OK，$(echo "$OUT" | grep -o '"counter_source":"[^"]*"')，耗时 $(echo "$OUT" | grep -o '"collect_ms":[0-9]*' | cut -d: -f2) ms" || echo "    采集器输出异常：$(echo "$OUT" | head -c 300)"
echo "    占用闪存约 $(( $(cat /www/cgi-bin/pulse /usr/share/pulse/* /etc/config/pulse /etc/sysctl.d/99-pulse.conf 2>/dev/null | wc -c) / 1024 )) KB（未压缩）"
echo
echo "口令:       $TOKEN   （以后可用 uci get pulse.main.token 查看）"
echo "测试采集器: curl -s 'http://$LANIP/cgi-bin/pulse?token=$TOKEN' | head -c 300"
echo "打开面板:   在电脑上双击 web/index.html → 点「连接路由器」→ 地址 http://$LANIP/cgi-bin/pulse，口令如上"
echo "诊断:       sh /usr/share/pulse/diag.sh"
echo "卸载:       sh /tmp/pulse-qwrt/uninstall.sh  （或重新上传后执行）"
