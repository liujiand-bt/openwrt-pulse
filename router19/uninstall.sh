#!/bin/sh
# 卸载 openwrt-pulse（常驻与临时两种安装都会清理）
sh /tmp/pulse/server.sh stop >/dev/null 2>&1
rm -f /www/cgi-bin/pulse /etc/sysctl.d/99-pulse.conf
rm -rf /usr/share/pulse /tmp/pulse /tmp/pulse-diag
# 如果用过 counters=iptables，删掉计数链
iptables -w -t mangle -D FORWARD -j pulse 2>/dev/null; iptables -w -t mangle -F pulse 2>/dev/null; iptables -w -t mangle -X pulse 2>/dev/null
if [ "$1" = "--all" ]; then rm -f /etc/config/pulse; echo "已删除配置 /etc/config/pulse"; else echo "保留 /etc/config/pulse（彻底删除请加 --all）"; fi
echo "已卸载。nf_conntrack_acct 仍为 1，重启后恢复固件默认值。"
