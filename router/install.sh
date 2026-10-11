#!/bin/sh
# 在 OpenWrt 路由器上执行（先把 openwrt-pulse 目录放到 /tmp/openwrt-pulse）：
#   sh /tmp/openwrt-pulse/router/install.sh             自动生成访问口令
#   sh /tmp/openwrt-pulse/router/install.sh --no-token  不设口令（内网任何人可看）
# 会安装：/www/cgi-bin/pulse（采集器）、/www/pulse/（前端）、/etc/config/pulse、/etc/init.d/pulse
# 已有 /etc/config/pulse 时保留原配置和原口令。
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
NO_TOKEN=0
for a in "$@"; do
	case "$a" in
	--no-token) NO_TOKEN=1 ;;
	-h|--help) sed -n '2,6p' "$0"; exit 0 ;;
	*) echo "未知参数: $a（可用: --no-token）"; exit 1 ;;
	esac
done
PM=opkg; command -v apk >/dev/null 2>&1 && PM=apk
echo "[1/4] 检查依赖（$PM）"
need=""
[ -x /usr/bin/ucode ] || need="$need ucode"
[ -e /usr/lib/ucode/fs.so ] || need="$need ucode-mod-fs"
[ -e /usr/lib/ucode/ubus.so ] || need="$need ucode-mod-ubus"
[ -e /usr/lib/ucode/uci.so ] || need="$need ucode-mod-uci"
command -v nft >/dev/null 2>&1 || need="$need nftables"
if [ -n "$need" ]; then
	echo "  安装:$need"
	if [ "$PM" = apk ]; then apk update && apk add $need; else opkg update && opkg install $need; fi
fi
echo "[2/4] 复制文件"
install -m 0755 "$HERE/files/www/cgi-bin/pulse" /www/cgi-bin/pulse
mkdir -p /www/pulse /usr/share/pulse
cp -r "$HERE/../web/." /www/pulse/
install -m 0755 "$HERE/files/usr/share/pulse/pulse-nft.sh" /usr/share/pulse/pulse-nft.sh
install -m 0755 "$HERE/files/etc/init.d/pulse" /etc/init.d/pulse
NEWCONF=0
if [ ! -f /etc/config/pulse ]; then install -m 0600 "$HERE/files/etc/config/pulse" /etc/config/pulse; NEWCONF=1; fi
TOKEN=$(uci -q get pulse.main.token || true)
if [ -z "$TOKEN" ] && [ "$NO_TOKEN" = 0 ]; then
	TOKEN=$(head -c 12 /dev/urandom | md5sum | cut -c1-16)
	uci set pulse.main.token="$TOKEN"
	uci commit pulse
	echo "  已生成访问口令"
elif [ -n "$TOKEN" ] && [ "$NEWCONF" = 0 ]; then
	echo "  保留已有配置与口令"
fi
echo "[3/4] 打开连接跟踪字节统计（conntrack 兜底模式需要）"
sysctl -w net.netfilter.nf_conntrack_acct=1 >/dev/null 2>&1 || true
grep -q nf_conntrack_acct /etc/sysctl.conf 2>/dev/null || echo 'net.netfilter.nf_conntrack_acct=1' >> /etc/sysctl.conf
echo "[4/4] 创建 nftables 每 IP 计数表"
/etc/init.d/pulse enable
/etc/init.d/pulse start || echo "  (nft 计数表创建失败，将回退到 bandix / conntrack / nlbwmon)"
if [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ]; then
	echo "!! 检测到 flow offloading 已开启：被卸载的连接不经过 forward 链，每设备速率会严重偏低。"
	echo "   如需准确数据：uci set firewall.@defaults[0].flow_offloading=0; uci set firewall.@defaults[0].flow_offloading_hw=0; uci commit firewall; /etc/init.d/firewall restart"
fi
LANIP=$(uci -q get network.lan.ipaddr || echo 192.168.1.1)
LANIP=${LANIP%/*}
echo
if [ -n "$TOKEN" ]; then
	echo "完成。口令: $TOKEN   （以后可用 uci get pulse.main.token 查看）"
	echo "浏览器打开: http://$LANIP/pulse/?token=$TOKEN"
	echo "测试采集器: curl -s 'http://$LANIP/cgi-bin/pulse?token=$TOKEN' | head -c 300"
else
	echo "完成（未设口令，内网任何人都能查看）。浏览器打开: http://$LANIP/pulse/"
	echo "以后要加口令: uci set pulse.main.token=\"\$(head -c 12 /dev/urandom | md5sum | cut -c1-16)\"; uci commit pulse"
fi
