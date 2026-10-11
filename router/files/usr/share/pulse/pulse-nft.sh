#!/bin/sh
# 创建/删除独立的 nftables 表 inet pulse，给内网每个 IPv4 地址做上下行字节计数。
# 独立表不会被 fw4 重载清掉，也不影响防火墙规则（policy accept，只计数）。
# 用法：pulse-nft.sh start|stop|status
[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
LAN=$(uci -q get pulse.main.lan_iface || echo lan)
cidr() {
	command -v network_get_subnet >/dev/null && network_get_subnet SUB "$LAN" && [ -n "$SUB" ] && { echo "$SUB"; return; }
	ip -4 -o addr show dev br-lan | awk '{print $4; exit}'
}
case "$1" in
start)
	NET=$(cidr); [ -z "$NET" ] && { echo "pulse: cannot detect LAN subnet" >&2; exit 1; }
	nft delete table inet pulse 2>/dev/null
	nft -f - <<NFT
table inet pulse {
	set dl4 { type ipv4_addr; size 1024; flags dynamic, timeout; timeout 1d; }
	set ul4 { type ipv4_addr; size 1024; flags dynamic, timeout; timeout 1d; }
	chain count_fwd {
		type filter hook forward priority -5; policy accept;
		ip daddr $NET ip saddr != $NET update @dl4 { ip daddr counter }
		ip saddr $NET ip daddr != $NET update @ul4 { ip saddr counter }
	}
}
NFT
	echo "pulse: counting $NET" ;;
stop) nft delete table inet pulse 2>/dev/null; echo "pulse: removed" ;;
status) nft list table inet pulse ;;
*) echo "usage: $0 start|stop|status"; exit 1 ;;
esac
