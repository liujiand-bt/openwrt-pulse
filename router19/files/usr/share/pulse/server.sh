#!/bin/sh
# 独立小网站：在 LAN IP 的 8088 端口提供前端 + 采集器（全部在 /tmp，重启即消失）
# 用法：sh server.sh start|stop|status [端口]
PORT=${2:-8088}; DIR=/tmp/pulse/www; PID=/tmp/pulse/server.pid
LANIP=$(uci -q get network.lan.ipaddr | cut -d/ -f1); [ -n "$LANIP" ] || LANIP=192.168.1.1
case "$1" in
start)
	[ -f "$DIR/cgi-bin/pulse" ] || { echo "缺少 $DIR/cgi-bin/pulse，请先运行 install.sh tmp"; exit 1; }
	"$0" stop >/dev/null 2>&1
	if command -v uhttpd >/dev/null; then
		uhttpd -f -p "$LANIP:$PORT" -h "$DIR" -x /cgi-bin -t 20 -T 20 -k 0 >/dev/null 2>&1 &
	elif busybox --list 2>/dev/null | grep -qx httpd; then
		busybox httpd -f -p "$LANIP:$PORT" -h "$DIR" >/dev/null 2>&1 &
	else echo "没有 uhttpd 也没有 busybox httpd"; exit 1; fi
	echo $! > "$PID"; sleep 1
	kill -0 "$(cat $PID)" 2>/dev/null && echo "已启动：http://$LANIP:$PORT/  （只监听内网地址）" || { echo "启动失败"; exit 1; } ;;
stop) [ -f "$PID" ] && kill "$(cat $PID)" 2>/dev/null; rm -f "$PID"; echo "已停止" ;;
status) [ -f "$PID" ] && kill -0 "$(cat $PID)" 2>/dev/null && echo "运行中 http://$LANIP:$PORT/" || echo "未运行" ;;
*) echo "用法: $0 start|stop|status [端口]"; exit 1 ;;
esac
