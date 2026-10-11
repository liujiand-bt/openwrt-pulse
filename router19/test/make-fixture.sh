#!/bin/sh
# 模拟 QWRT / OpenWrt 19.07（JDCloud AX1800 Pro, IPQ6018, 内核 4.4.60, ECM/NSS）的文件与命令输出。
# 只用于在 PC 上验证 Lua 采集器和 diag.sh 的解析逻辑，不代表真机行为。
# 用法：make-fixture.sh <T秒>   T 越大，计数器越大；T>=2 时一条连接结束、一条新连接出现
set -e
D=$(cd "$(dirname "$0")" && pwd); R=$D/root; B=$D/bin
T=${1:-0}
rm -rf "$R" "$B"; mkdir -p "$R/proc/net" "$R/proc/sys/net/netfilter" "$R/proc/sys/kernel" "$R/tmp/sysinfo" "$R/etc" "$B"
echo QWRT > "$R/proc/sys/kernel/hostname"
echo "JDCloud AX1800 Pro" > "$R/tmp/sysinfo/model"
cat > "$R/etc/openwrt_release" <<X
DISTRIB_ID='QWRT'
DISTRIB_RELEASE='R24.5.1'
DISTRIB_DESCRIPTION='QWRT R24.5.1'
DISTRIB_TAINTS='no-all busybox'
X
printf 'MemTotal:         415744 kB\nMemFree:           60000 kB\nMemAvailable:     200704 kB\nCached:            90000 kB\n' > "$R/proc/meminfo"
echo "0.31 0.28 0.25 1/150 4567" > "$R/proc/loadavg"
echo "$((360000 + T)).42 700000.00" > "$R/proc/uptime"
printf 'ecm 245760 0 - Live 0x0000000000000000\nqca_nss_drv 1000 40 ecm, Live 0x0\nnf_conntrack 100000 40 ecm,xt_FULLCONENAT, Live 0x0\nhyfi_bridging 1000 0 - Live 0x0\n' > "$R/proc/modules"
cat > "$R/proc/net/dev" <<X
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  1000 10 0 0 0 0 0 0  1000 10 0 0 0 0 0 0
  eth0: $((8000000000 + T*31000000)) 1 0 0 0 0 0 0 $((1000000000 + T*3000000)) 1 0 0 0 0 0 0
 br-lan: $((700000000 + T*2500000)) 1 0 0 0 0 0 0 $((6000000000 + T*25000000)) 1 0 0 0 0 0 0
pppoe-wan: $((7900000000 + T*30000000)) 1 0 0 0 0 0 0 $((950000000 + T*2800000)) 1 0 0 0 0 0 0
  wifi0: 1 1 0 0 0 0 0 0 1 1 0 0 0 0 0 0
  wifi1: 1 1 0 0 0 0 0 0 1 1 0 0 0 0 0 0
  ath0: $((50000000 + T*20000)) 1 0 0 0 0 0 0 $((90000000 + T*100000)) 1 0 0 0 0 0 0
  ath1: $((300000000 + T*1000000)) 1 0 0 0 0 0 0 $((4000000000 + T*12000000)) 1 0 0 0 0 0 0
   wg0: $((20000000 + T*50000)) 1 0 0 0 0 0 0 $((60000000 + T*250000)) 1 0 0 0 0 0 0
X
cat > "$R/proc/net/wireless" <<X
Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE
 face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22
  ath0: 0000    0.  -95.  -95.       0      0      0      0      0        0
  ath1: 0000    0.  -95.  -95.       0      0      0      0      0        0
X
cat > "$R/proc/net/arp" <<X
IP address       HW type     Flags       HW address            Mask     Device
192.168.1.41     0x1         0x2         3c:7c:3f:1a:22:01     *        br-lan
192.168.1.10     0x1         0x2         00:11:32:aa:5e:02     *        br-lan
192.168.1.102    0x1         0x2         a8:5c:2c:61:7f:12     *        br-lan
192.168.1.104    0x1         0x2         50:ec:50:1d:28:14     *        br-lan
192.168.1.140    0x1         0x2         04:d3:b0:7b:2b:27     *        br-lan
192.168.1.66     0x1         0x0         00:00:00:00:00:00     *        br-lan
X
# conntrack：ECM 回写的字节数体现在 bytes= 里
C1=$((10000 + T*400000)); C2=$((5000000 + T*3000000))      # 书房台式机 一条 HTTPS 下载：上行/下行
M1=$((2000 + T*100000)); M2=$((800000 + T*1500000))         # MacBook 一条 QUIC
{
echo "ipv4     2 tcp      6 7440 ESTABLISHED src=192.168.1.41 dst=1.1.1.1 sport=50000 dport=443 packets=10 bytes=$C1 src=1.1.1.1 dst=100.64.1.2 sport=443 dport=50000 packets=20 bytes=$C2 [ASSURED] mark=0 zone=0 use=2"
echo "ipv4     2 udp      17 170 src=192.168.1.102 dst=142.250.1.1 sport=55555 dport=443 packets=5 bytes=$M1 src=142.250.1.1 dst=100.64.1.2 sport=443 dport=55555 packets=9 bytes=$M2 [ASSURED] mark=0 zone=0 use=2"
# 端口转发进来的连接：外部 -> WAN:8443 -> NAS 192.168.1.10:443（NAS 上传为 reply 方向）
echo "ipv4     2 tcp      6 7440 ESTABLISHED src=203.0.113.7 dst=100.64.1.2 sport=40000 dport=8443 packets=3 bytes=$((1000 + T*20000)) src=192.168.1.10 dst=203.0.113.7 sport=443 dport=40000 packets=3 bytes=$((90000 + T*2000000)) [ASSURED] mark=0 zone=0 use=2"
# 路由器自己的连接（不应计入任何设备）
echo "ipv4     2 udp      17 20 src=100.64.1.2 dst=119.29.29.29 sport=5353 dport=53 packets=1 bytes=70 src=119.29.29.29 dst=100.64.1.2 sport=53 dport=5353 packets=1 bytes=120 mark=0 zone=0 use=2"
# IPv6：MacBook 的公网 v6 地址
echo "ipv6     10 tcp      6 7440 ESTABLISHED src=240e:3b0:1::102 dst=2400:3200::1 sport=50010 dport=443 packets=2 bytes=$((500 + T*10000)) src=2400:3200::1 dst=240e:3b0:1::102 sport=443 dport=50010 packets=2 bytes=$((4000 + T*500000)) [ASSURED] mark=0 zone=0 use=2"
if [ "$T" -lt 2 ]; then
echo "ipv4     2 tcp      6 100 ESTABLISHED src=192.168.1.104 dst=8.8.8.8 sport=4444 dport=443 packets=1 bytes=$((100 + T*1000)) src=8.8.8.8 dst=100.64.1.2 sport=443 dport=4444 packets=1 bytes=$((1000 + T*50000)) [ASSURED] mark=0 zone=0 use=2"
else
echo "ipv4     2 tcp      6 100 ESTABLISHED src=192.168.1.104 dst=9.9.9.9 sport=4445 dport=443 packets=1 bytes=$(( (T-1)*1000 )) src=9.9.9.9 dst=100.64.1.2 sport=443 dport=4445 packets=1 bytes=$(( (T-1)*50000 )) [ASSURED] mark=0 zone=0 use=2"
fi
} > "$R/proc/net/nf_conntrack"
echo 6 > "$R/proc/sys/net/netfilter/nf_conntrack_count"
echo 65536 > "$R/proc/sys/net/netfilter/nf_conntrack_max"
echo ${ACCT:-1} > "$R/proc/sys/net/netfilter/nf_conntrack_acct"
NOW=$(date +%s)
cat > "$R/tmp/dhcp.leases" <<X
$((NOW+40000)) 3c:7c:3f:1a:22:01 192.168.1.41 DESKTOP-ABC 01:3c:7c:3f:1a:22:01
$((NOW+30000)) 00:11:32:aa:5e:02 192.168.1.10 * *
$((NOW+20000)) a8:5c:2c:61:7f:12 192.168.1.102 MacBook-Air *
$((NOW+10000)) 50:ec:50:1d:28:14 192.168.1.104 xiaomi-speaker *
$((NOW+50000)) 04:d3:b0:7b:2b:27 192.168.1.140 DESKTOP-ASLUHVI 01:04:d3:b0:7b:2b:27
X
# ---- 命令替身 ----
cat > "$B/ubus" <<'X'
#!/bin/sh
# 真机 ubus 输出是 tab 缩进、一行一个键的 JSON，这里用 python 排版模拟
pretty() { python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin), indent='\t'))"; }
{ case "$2 $3" in
"network.interface dump") cat <<J
{"interface":[{"interface":"lan","up":true,"proto":"static","l3_device":"br-lan","device":"br-lan","ipv4-address":[{"address":"192.168.1.1","mask":24}]},
{"interface":"wan","up":true,"proto":"pppoe","l3_device":"pppoe-wan","device":"eth0","ipv4-address":[{"address":"100.64.1.2","mask":32}]},
{"interface":"wan6","up":true,"proto":"dhcpv6","l3_device":"pppoe-wan","ipv6-address":[{"address":"240e:3b0:ffff::1","mask":64}]},
{"interface":"wg0","up":true,"proto":"wireguard","l3_device":"wg0","ipv4-address":[{"address":"10.8.0.1","mask":24}]},
{"interface":"loopback","up":true,"proto":"static","l3_device":"lo","ipv4-address":[{"address":"127.0.0.1","mask":8}]}]}
J
;;
"network.interface.wan status") echo '{"up":true,"l3_device":"pppoe-wan","device":"eth0","proto":"pppoe"}' ;;
"network.device status") echo '{"br-lan":{"up":true,"speed":"1000F"},"eth0":{"up":true,"speed":"1000F"},"pppoe-wan":{"up":true}}' ;;
"network.wireless status") echo '{}' ;;
*) exit 4 ;;
esac; } | pretty
X
cat > "$B/iwinfo" <<'X'
#!/bin/sh
case "$1 $2" in
"ath1 info") cat <<I
ath1      ESSID: "JDC-5G"
          Access Point: 00:11:22:33:44:55
          Mode: Master  Channel: 149 (5.745 GHz)
          Tx-Power: 20 dBm  Link Quality: unknown/70
          Signal: unknown  Noise: -95 dBm
          Bit Rate: unknown
          Encryption: WPA2 PSK (CCMP)
          Type: wext  HW Mode(s): 802.11nac
          Hardware: unknown [Generic WEXT]
          TX power offset: unknown
          Frequency offset: unknown
          Supports VAPs: no  PHY name: ath1
I
;;
"ath1 assoclist") cat <<I
A8:5C:2C:61:7F:12  -55 dBm / -95 dBm (SNR 40)  10 ms ago
	RX: 866.7 MBit/s, VHT-MCS 9, 80MHz, VHT-NSS 2      12345 Pkts.
	TX: 866.7 MBit/s, VHT-MCS 9, 80MHz, VHT-NSS 2      23456 Pkts.
	expected throughput: unknown

F2:1A:9C:44:01:11  -48 dBm / -95 dBm (SNR 47)  0 ms ago
	RX: 433.3 MBit/s                                   100 Pkts.
	TX: 433.3 MBit/s                                   200 Pkts.
	expected throughput: unknown

I
;;
"ath0 info") printf 'ath0      ESSID: "JDC-2.4G"\n          Mode: Master  Channel: 6 (2.437 GHz)\n' ;;
"ath0 assoclist") cat <<I
00:00:00:50:3D:B5  -62 dBm / -95 dBm (SNR 33)  5 ms ago
	RX: 72.2 MBit/s                                    999 Pkts.
	TX: 72.2 MBit/s                                    888 Pkts.
	expected throughput: unknown

50:EC:50:1D:28:14  -57 dBm / -95 dBm (SNR 38)  20 ms ago
	RX: 65.0 MBit/s                                    100 Pkts.
	TX: 72.0 MBit/s                                    200 Pkts.
	expected throughput: unknown

I
;;
*) exit 1 ;;
esac
X
cat > "$B/wlanconfig" <<'X'
#!/bin/sh
case "$1 $2 $3" in
"ath0 list sta")
echo "ADDR               AID CHAN TXRATE RXRATE RSSI MINRSSI MAXRSSI IDLE  TXSEQ  RXSEQ  CAPS XCAPS ACAPS     ERP    STATE MAXRATE(DOT11) HTCAPS ASSOCTIME    IEs   MODE PSMODE RXNSS TXNSS"
echo "50:ec:50:1d:28:14    1    6  72M     65M   38      31      45    0      0   65535   ES         0       b              0           WPS     00:12:34 RSN WME IEEE80211_MODE_11NG_HT20  0 1 1"
echo "04:d3:b0:7b:2b:27    2    6 144M    130M   33      28      40    0      0   65535   ES         0       b              0                 01:02:03 RSN WME IEEE80211_MODE_11NG_HT20  0 1 1"
;;
"ath1 list sta")
echo "ADDR               AID CHAN TXRATE RXRATE RSSI MINRSSI MAXRSSI IDLE  TXSEQ  RXSEQ  CAPS XCAPS ACAPS     ERP    STATE MAXRATE(DOT11) HTCAPS ASSOCTIME    IEs   MODE PSMODE RXNSS TXNSS"
echo "a8:5c:2c:61:7f:12    1  149 866M    866M   40      35      45    0      0   65535   ES         0       b              0                 00:12:34 RSN WME IEEE80211_MODE_11AC_VHT80 0 2 2"
echo "f2:1a:9c:44:01:11    2  149 433M    433M   47      40      50    0      0   65535   ES         0       b              0                 00:01:02 RSN WME IEEE80211_MODE_11AC_VHT80 0 1 1"
;;
*) exit 1 ;;
esac
X
cat > "$B/uci" <<'X'
#!/bin/sh
[ "$1" = "-q" ] && shift
[ "$1" = "show" ] || exit 1
case "$2" in
pulse) printf "pulse.main=pulse\npulse.main.token='${PULSE_TEST_TOKEN:-}'\npulse.main.counters='${PULSE_TEST_COUNTERS:-auto}'\npulse.main.cors_origin='*'\n" ;;
dhcp) printf "dhcp.lan=dhcp\ndhcp.cfg01a1b2=host\ndhcp.cfg01a1b2.name='NAS-DS920'\ndhcp.cfg01a1b2.mac='00:11:32:AA:5E:02'\n" ;;
network) printf "network.wg0=interface\nnetwork.cfg0b1234=wireguard_wg0\nnetwork.cfg0b1234.public_key='PEERKEY1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa='\nnetwork.cfg0b1234.description='我的手机'\nnetwork.cfg0b1234.allowed_ips='10.8.0.2/32'\n" ;;
*) exit 1 ;;
esac
X
cat > "$B/ip" <<'X'
#!/bin/sh
case "$*" in
"-6 neigh show dev br-lan") printf '240e:3b0:1::102 lladdr a8:5c:2c:61:7f:12 REACHABLE\nfe80::1 lladdr a8:5c:2c:61:7f:12 STALE\n' ;;
*) exit 1 ;;
esac
X
cat > "$B/wg" <<X
#!/bin/sh
printf 'wg0\tPRIVATEKEY-MUST-NOT-LEAK=\tSERVERPUB=\t51820\toff\n'
printf 'wg0\tPEERKEY1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=\t(none)\t117.136.1.2:41820\t10.8.0.2/32\t$((NOW-30))\t$((1000000 + T*50000))\t$((5000000 + T*250000))\t25\n'
X
chmod +x "$B"/*
ln -sf "$(command -v lua5.1)" "$B/lua"
