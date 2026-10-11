#!/bin/sh
# openwrt-pulse 诊断（busybox ash）：检查各数据源是否可用，并做 5 秒准确性对比。
# 用法：sh /usr/share/pulse/diag.sh [--raw]      默认对 MAC / 公网 IP 打码，方便直接贴出来
#       也可以不安装直接跑：ssh root@192.168.1.1 'sh -s' < diag.sh
RAW=0; [ "$1" = "--raw" ] && RAW=1
R=${PULSE_ROOT:-}
WAIT=${PULSE_DIAG_WAIT:-5}
ok() { echo "  [OK] $*"; }
no() { echo "  [--] $*"; }
bad() { echo "  [!!] $*"; }
has() { command -v "$1" >/dev/null 2>&1; }
rd() { cat "$R$1" 2>/dev/null; }
mask() {
	if [ $RAW = 1 ]; then cat; else
	sed -E 's/([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}):[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}/\1:xx:xx:xx/g' | awk '{
		out = ""; s = $0
		while (match(s, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|[23][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F:]+/)) {
			t = substr(s, RSTART, RLENGTH)
			if (t ~ /:/) { n = split(t, g, ":"); if (n > 2) t = g[1] ":" g[2] ":x:x" }
			else { split(t, o, "."); a = o[1] + 0; b = o[2] + 0
				if (!(a == 10 || a == 127 || a == 0 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 100 && b >= 64 && b <= 127))) t = o[1] "." o[2] ".x.x" }
			out = out substr(s, 1, RSTART - 1) t; s = substr(s, RSTART + RLENGTH)
		}
		print out s }'
	fi
}
main() {
echo "== openwrt-pulse diag $(date '+%F %T') =="
echo "[系统]"
echo "  型号: $(rd /tmp/sysinfo/model)"
echo "  固件: $(rd /etc/openwrt_release | sed -n "s/DISTRIB_DESCRIPTION='\(.*\)'/\1/p")  内核: $(uname -r 2>/dev/null)  架构: $(uname -m 2>/dev/null)"
echo "  内存: $(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%d MB / 可用 %d MB",t/1024,a/1024}' $R/proc/meminfo)  负载: $(cut -d' ' -f1-3 $R/proc/loadavg)"
df -k /overlay 2>/dev/null | awk 'NR==2{printf "  overlay: 共 %d KB，剩余 %d KB\n",$2,$4}'

echo "[运行环境]"
if has lua; then
	ok "lua: $(lua -v 2>&1 | head -1)"
	for m in ubus iwinfo uci nixio luci.jsonc; do
		if lua -e "require '$m'" >/dev/null 2>&1; then ok "  lua 模块 $m"; else no "  lua 模块 $m（会用命令行替代）"; fi
	done
else bad "没有 lua：Lua 采集器无法运行，请把这段输出发给我们"; fi
has ucode && ok "ucode 存在（可用 ucode 版采集器）" || no "没有 ucode（用 Lua 版采集器）"
for c in ubus iwinfo wlanconfig wg conntrack iptables nft ip uhttpd; do has $c && ok "命令 $c" || no "命令 $c"; done
if pidof uhttpd >/dev/null 2>&1; then
	ok "uhttpd 运行中，监听: $(uci -q get uhttpd.main.listen_http | tr '\n' ' ')  cgi_prefix: $(uci -q get uhttpd.main.cgi_prefix)"
else bad "uhttpd 没有运行"; fi

echo "[网络接口]"
if has ubus && ubus call network.interface dump >/dev/null 2>&1; then
	ubus call network.interface dump 2>/dev/null | awk -F'"' '/"interface":/{i=$4} /"l3_device":/{print "  " i " -> " $4}' | sort -u | mask
else bad "ubus network.interface dump 失败"; fi
WANDEV=$(ubus call network.interface.wan status 2>/dev/null | sed -n 's/.*"l3_device": *"\([^"]*\)".*/\1/p' | head -1)
WANLOW=$(ubus call network.interface.wan status 2>/dev/null | sed -n 's/.*"device": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$WANDEV" ] || WANDEV=pppoe-wan
echo "  WAN 三层设备: $WANDEV  底层设备: ${WANLOW:-?}"

echo "[连接跟踪]"
CNT=$(rd /proc/sys/net/netfilter/nf_conntrack_count); MAX=$(rd /proc/sys/net/netfilter/nf_conntrack_max)
echo "  连接数: ${CNT:-?} / ${MAX:-?}"
ACCT=$(rd /proc/sys/net/netfilter/nf_conntrack_acct)
[ "$ACCT" = 1 ] && ok "nf_conntrack_acct=1" || bad "nf_conntrack_acct=${ACCT:-?}（需要改成 1：sysctl -w net.netfilter.nf_conntrack_acct=1）"
if [ -r "$R/proc/net/nf_conntrack" ]; then
	CT="$R/proc/net/nf_conntrack"; ok "/proc/net/nf_conntrack 可读"
elif has conntrack; then
	conntrack -L -o extended > /tmp/pulse-ct.txt 2>/dev/null; CT=/tmp/pulse-ct.txt; no "/proc/net/nf_conntrack 不存在，改用 conntrack -L"
fi
if [ -n "$CT" ]; then
	awk '{n++; if(/bytes=/)b++} END{printf "  样本 %d 条，其中带 bytes= 的 %d 条\n",n,b}' "$CT"
fi

echo "[硬件加速]"
if grep -q '^ecm ' $R/proc/modules 2>/dev/null; then
	bad "已加载 ECM（高通 NSS 硬件加速）：加速后的包不经过 netfilter，iptables/nft 计数会严重偏低；ECM 会把字节数每秒左右回写到 conntrack（需 acct=1）"
	for f in /sys/kernel/debug/ecm/ecm_db/connection_count_simple /sys/kernel/debug/ecm/ecm_nss_ipv4/accelerated_count; do
		[ -r "$f" ] && echo "    $(basename $(dirname $f))/$(basename $f): $(cat $f 2>/dev/null)"
	done
	[ -d /sys/kernel/debug/ecm ] || no "未挂载 debugfs 或无 /sys/kernel/debug/ecm（不影响使用）"
else no "未检测到 ECM 模块"; fi
grep -q '^qca_nss' $R/proc/modules 2>/dev/null && echo "  NSS 模块: $(grep -o '^qca_nss[a-z_]*' $R/proc/modules | tr '\n' ' ')"
echo "  firewall flow_offloading=$(uci -q get firewall.@defaults[0].flow_offloading) flow_offloading_hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)"

echo "[无线]"
for d in $(awk -F: 'NR>2{gsub(/ /,"",$1); print $1}' $R/proc/net/wireless 2>/dev/null; awk -F: 'NR>2{gsub(/ /,"",$1); print $1}' $R/proc/net/dev | grep -E '^(ath[0-9]|wlan[0-9]|phy[0-9]+-ap)' ) ; do echo $d; done | sort -u | while read d; do
	ss=$(iwinfo $d info 2>/dev/null | sed -n 's/.*ESSID: "\(.*\)".*/\1/p')
	ty=$(iwinfo $d info 2>/dev/null | sed -n 's/.*Type: \(\S*\).*/\1/p')
	IW=$(iwinfo $d assoclist 2>/dev/null)
	WC=$(wlanconfig $d list sta 2>/dev/null)
	n1=$(printf '%s\n' "$IW" | grep -cE '^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}')
	n2=$(printf '%s\n' "$WC" | grep -cE '^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}')
	echo "  $d  SSID=${ss:-?}  type=${ty:-?}  iwinfo 客户端=$n1  wlanconfig 客户端=$n2"
	printf '%s\n' "$IW" | grep -E '^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}' | while read mac rest; do
		sig=$(printf '%s' "$rest" | sed -n 's/^[^0-9-]*\(-*[0-9][0-9]*\) dBm.*/\1/p')
		bad=""; printf '%s' "$mac" | grep -qiE '^00:00:00:' && bad="  ← 可疑（高通 iwinfo 错位？）"
		echo "    iwinfo     $mac  ${sig:+${sig} dBm}$bad"
	done
	printf '%s\n' "$WC" | grep -E '^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}' | while read mac rest; do
		echo "    wlanconfig $mac"
	done
done
# 交叉核对：ARP 在线设备是否出现在无线客户端列表
: > /tmp/pulse-wifi-macs.txt
for d in ath0 ath1 ath2 ath3 wlan0 wlan1; do
	iwinfo $d assoclist 2>/dev/null
	wlanconfig $d list sta 2>/dev/null
done | grep -oiE '^[0-9a-f]{2}([:-][0-9a-f]{2}){5}' | tr 'A-F' 'a-f' | tr '-' ':' >> /tmp/pulse-wifi-macs.txt
echo "  [交叉] ARP 在线 vs 无线 assoc："
awk 'NR>1 && $3=="0x2" && $4!="00:00:00:00:00:00"{print tolower($4), $1}' $R/proc/net/arp 2>/dev/null | while read mac ip; do
	mac=$(echo "$mac" | tr '-' ':')
	if grep -qx "$mac" /tmp/pulse-wifi-macs.txt 2>/dev/null; then
		echo "    $ip  $mac  → 无线"
	else
		echo "    $ip  $mac  → 仅 ARP（采集器会标成有线；若实际是 WiFi，看上面 iwinfo 是否出现 00:00:00: 开头的错位 MAC）"
	fi
done
rm -f /tmp/pulse-wifi-macs.txt

echo "[WireGuard]"
if has wg; then echo "  对端数: $(wg show all dump 2>/dev/null | awk -F'\t' 'NF==9' | wc -l)"; else no "无 wg 命令"; fi
echo "[IPv6 邻居]"
n6=$(ip -6 neigh show dev br-lan 2>/dev/null | grep -c lladdr); echo "  br-lan IPv6 邻居: ${n6:-0}（>0 时可把 IPv6 流量算到设备上）"

echo "[${WAIT} 秒准确性对比] 建议此时在某台设备上跑测速 / 下载大文件"
snap() {
	awk -v w="$WANDEV" -v l="$WANLOW" -F'[: ]+' '{sub(/^ +/,"")} $1==w{wr=$2;wt=$10} $1==l{lr=$2;lt=$10} END{print wr+0, wt+0, lr+0, lt+0}' $R/proc/net/dev
	if [ -n "$CT" ]; then
		[ "$CT" = /tmp/pulse-ct.txt ] && conntrack -L -o extended > /tmp/pulse-ct.txt 2>/dev/null
		awk '{n=0; for(i=1;i<=NF;i++) if($i ~ /^bytes=/){n++; v=substr($i,7); if(n==1)o+=v; else r+=v}} END{printf "%.0f %.0f\n", o, r}' "$CT"
	else echo "0 0"; fi
	iptables -w -t mangle -nvxL pulse 2>/dev/null | awk 'NR>2{s+=$2} END{printf "%.0f\n", s}'
}
A=$(snap | tr '\n' ' '); sleep $WAIT; B=$(snap | tr '\n' ' ')
echo "$A $B" | awk -v t=$WAIT '{
	n=7; split($0,v," ");
	wr=(v[n+1]-v[1])*8/t/1e6; wt=(v[n+2]-v[2])*8/t/1e6; lr=(v[n+3]-v[3])*8/t/1e6; lt=(v[n+4]-v[4])*8/t/1e6
	co=(v[n+5]-v[5])*8/t/1e6; cr=(v[n+6]-v[6])*8/t/1e6; ip=(v[n+7]-v[7])*8/t/1e6
	printf "  WAN 接口 (三层)  ↓ %.1f  ↑ %.1f Mbps\n", wr, wt
	printf "  WAN 底层网口     ↓ %.1f  ↑ %.1f Mbps\n", lr, lt
	printf "  conntrack 总和   reply %.1f  orig %.1f Mbps（含连接结束的误差）\n", cr, co
	if (ip>0) printf "  iptables pulse 链 %.1f Mbps\n", ip
	if (wr > 5) { printf "  → conntrack 下行 / WAN 下行 = %.0f%%\n", cr/wr*100 }
	else print "  → WAN 流量太小，无法判断比例；请边下载边重跑"
	if (lr > 5 && wr < lr*0.5) print "  → 三层 WAN 计数明显低于底层网口：建议 uci set pulse.main.wan_stats_dev=<底层网口>"
}'

echo "[采集器]"
P=$PULSE_CGI
[ -z "$P" ] && [ -f /www/cgi-bin/pulse ] && P=/www/cgi-bin/pulse
[ -z "$P" ] && [ -f /tmp/pulse/www/cgi-bin/pulse ] && P=/tmp/pulse/www/cgi-bin/pulse
if [ -n "$P" ]; then
	T=$(uci -q get pulse.main.token)
	OUT=$(QUERY_STRING= HTTP_X_PULSE_TOKEN="$T" REQUEST_METHOD=GET PULSE_STATE=/tmp/pulse-diag lua "$P" 2>&1 | sed '1,/^\r*$/d')
	echo "$OUT" | grep -q '"collector"' && ok "$P 运行正常（输出 $(echo "$OUT" | wc -c) 字节）" || bad "$P 输出异常: $(echo "$OUT" | head -c 300)"
	echo "  $(echo "$OUT" | grep -o '"counter_source":"[^"]*"\|"collect_ms":[0-9]*\|"accel":"[^"]*"' | tr '\n' ' ')"
	echo "  设备数: $(echo "$OUT" | grep -o '"link":' | wc -l)  WG 对端: $(echo "$OUT" | grep -o '"pubkey":' | wc -l)"
	echo "$OUT" | grep -o '"warnings":\[[^]]*\]' | sed 's/^/  /'
	rm -rf /tmp/pulse-diag
else no "未安装采集器（只做了环境检查）"; fi
SZ=$(cat /www/cgi-bin/pulse /usr/share/pulse/* /etc/config/pulse 2>/dev/null | wc -c); [ "$SZ" -gt 0 ] && echo "  pulse 占用闪存约 $((SZ / 1024)) KB"
echo "== end =="
}
main 2>&1 | mask
