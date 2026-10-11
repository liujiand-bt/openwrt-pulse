#!/bin/sh
# 生成一个假的 OpenWrt 根目录 + 假 ubus/uci 模块 + 假 nft/wg 命令，用来在 PC 上离线跑采集器。
# 这只验证脚本逻辑与 JSON 结构，不代表真实路由器上的行为。
set -e
D=$(cd "$(dirname "$0")" && pwd); R=$D/root; B=$D/bin; L=$D/lib
rm -rf "$R" "$B" "$L"; mkdir -p "$R/proc/net" "$R/proc/sys/net/netfilter" "$R/proc/sys/kernel" "$R/tmp/sysinfo" "$R/etc" "$B" "$L"
echo OpenWrt > "$R/proc/sys/kernel/hostname"
echo "Xiaomi Redmi Router AX6000 (fixture)" > "$R/tmp/sysinfo/model"
echo "DISTRIB_DESCRIPTION='OpenWrt 24.10.3 r28959'" > "$R/etc/openwrt_release"
printf 'MemTotal:         491520 kB\nMemFree:          120000 kB\nMemAvailable:     330000 kB\n' > "$R/proc/meminfo"
echo "0.12 0.20 0.18 1/120 3456" > "$R/proc/loadavg"
echo "864321.55 1700000.00" > "$R/proc/uptime"
T=${1:-0}   # 时间偏移，让计数器增长
cat > "$R/proc/net/dev" <<X
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1000 10 0 0 0 0 0 0 1000 10 0 0 0 0 0 0
br-lan: $((900000000 + T*2000000)) 1 0 0 0 0 0 0 $((5000000000 + T*15000000)) 1 0 0 0 0 0 0
pppoe-wan: $((5000000000 + T*15000000)) 1 0 0 0 0 0 0 $((900000000 + T*2000000)) 1 0 0 0 0 0 0
phy1-ap0: $((100000000 + T*500000)) 1 0 0 0 0 0 0 $((3000000000 + T*9000000)) 1 0 0 0 0 0 0
wg0: $((20000000 + T*100000)) 1 0 0 0 0 0 0 $((80000000 + T*400000)) 1 0 0 0 0 0 0
X
cat > "$R/proc/net/arp" <<X
IP address       HW type     Flags       HW address            Mask     Device
192.168.1.41     0x1         0x2         3c:7c:3f:1a:22:01     *        br-lan
192.168.1.10     0x1         0x2         00:11:32:aa:5e:02     *        br-lan
192.168.1.102    0x1         0x2         a8:5c:2c:61:7f:12     *        br-lan
192.168.1.77     0x1         0x0         00:00:00:00:00:00     *        br-lan
100.64.0.1       0x1         0x2         aa:bb:cc:00:00:01     *        pppoe-wan
X
cat > "$R/proc/net/nf_conntrack" <<X
ipv4     2 tcp      6 7440 ESTABLISHED src=192.168.1.41 dst=1.1.1.1 sport=50000 dport=443 packets=10 bytes=2000 src=1.1.1.1 dst=113.87.1.2 sport=443 dport=50000 packets=20 bytes=90000 [ASSURED] mark=0 zone=0 use=2
ipv4     2 udp      17 60 src=192.168.1.102 dst=8.8.8.8 sport=5353 dport=53 packets=1 bytes=80 src=8.8.8.8 dst=113.87.1.2 sport=53 dport=5353 packets=1 bytes=120 mark=0 zone=0 use=2
ipv4     2 tcp      6 7440 ESTABLISHED src=192.168.1.41 dst=8.8.4.4 sport=50001 dport=443 packets=10 bytes=1000 src=8.8.4.4 dst=113.87.1.2 sport=443 dport=50001 packets=20 bytes=30000 [ASSURED] mark=0 zone=0 use=2
X
echo 3 > "$R/proc/sys/net/netfilter/nf_conntrack_count"
echo 16384 > "$R/proc/sys/net/netfilter/nf_conntrack_max"
echo 1 > "$R/proc/sys/net/netfilter/nf_conntrack_acct"
NOW=$(date +%s)
cat > "$R/tmp/dhcp.leases" <<X
$((NOW+40000)) 3c:7c:3f:1a:22:01 192.168.1.41 DESKTOP-ABC 01:3c:7c:3f:1a:22:01
$((NOW+30000)) 00:11:32:aa:5e:02 192.168.1.10 * *
$((NOW+20000)) a8:5c:2c:61:7f:12 192.168.1.102 MacBook-Air *
X
cat > "$L/ubus.uc" <<'X'
// 假 ubus 模块：按 "对象.方法[.device]" 返回固定数据
let FIX = {
  'network.interface.dump': { interface: [
    { interface: 'lan', up: true, proto: 'static', l3_device: 'br-lan', device: 'br-lan', 'ipv4-address': [{ address: '192.168.1.1', mask: 24 }] },
    { interface: 'wan', up: true, proto: 'pppoe', l3_device: 'pppoe-wan', device: 'wan', 'ipv4-address': [{ address: '113.87.1.2', mask: 32 }] },
    { interface: 'wan6', up: true, proto: 'dhcpv6', l3_device: 'pppoe-wan', 'ipv6-address': [{ address: '240e:3b0::1234', mask: 64 }] },
    { interface: 'wg0', up: true, proto: 'wireguard', l3_device: 'wg0', 'ipv4-address': [{ address: '10.8.0.1', mask: 24 }] },
    { interface: 'loopback', up: true, proto: 'static', l3_device: 'lo' } ] },
  'network.device.status': { 'br-lan': { up: true, speed: '1000F' }, 'pppoe-wan': { up: true } },
  'iwinfo.devices': { devices: ['phy1-ap0'] },
  'iwinfo.info.phy1-ap0': { ssid: 'Home-5G', frequency: 5745, channel: 149, mode: 'Master' },
  'iwinfo.assoclist.phy1-ap0': { results: [{ mac: 'A8:5C:2C:61:7F:12', signal: -55 }, { mac: 'F2:1A:9C:44:01:11', signal: -48 }] }
};
return { connect: () => ({ call: (o, m, a) => FIX[o + '.' + m + (a?.device ? '.' + a.device : '')] }) };
X
cat > "$L/uci.uc" <<'X'
let DATA = {
  pulse: { main: { '.type': 'pulse', '.name': 'main', token: '', counters: 'auto' } },
  dhcp: { h1: { '.type': 'host', '.name': 'h1', name: 'NAS-DS920', mac: '00:11:32:AA:5E:02', ip: '192.168.1.10' } },
  network: { p1: { '.type': 'wireguard_wg0', '.name': 'p1', public_key: 'PEERKEY1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=', description: '我的手机', allowed_ips: ['10.8.0.2/32'] } }
};
return { cursor: () => ({
  get: (c, s, o) => DATA[c]?.[s]?.[o],
  foreach: (c, t, fn) => { for (let k in DATA[c] ?? {}) { let s = DATA[c][k]; if (t == null || s['.type'] == t) fn(s); } }
}) };
X
cat > "$B/nft" <<X
#!/bin/sh
case "\$*" in
 *dl4*) echo '{"nftables":[{"metainfo":{"version":"1.0.9"}},{"set":{"family":"inet","name":"dl4","table":"pulse","type":"ipv4_addr","flags":["dynamic"],"elem":[{"elem":{"val":"192.168.1.41","counter":{"packets":100,"bytes":$((800000000 + T*3000000))}}},{"elem":{"val":"192.168.1.102","counter":{"packets":9,"bytes":$((2000000000 + T*9000000))}}},{"elem":{"val":"192.168.1.10","counter":{"packets":9,"bytes":$((10000 + T*100000))}}}]}}]}' ;;
 *ul4*) echo '{"nftables":[{"metainfo":{"version":"1.0.9"}},{"set":{"family":"inet","name":"ul4","table":"pulse","type":"ipv4_addr","flags":["dynamic"],"elem":[{"elem":{"val":"192.168.1.41","counter":{"packets":1,"bytes":$((90000000 + T*500000))}}},{"elem":{"val":"192.168.1.10","counter":{"packets":1,"bytes":$((40000000 + T*2000000))}}}]}}]}' ;;
 *) exit 1 ;;
esac
X
cat > "$B/wg" <<X
#!/bin/sh
printf 'wg0\tPRIVATEKEY-MUST-NOT-LEAK=\tSERVERPUB=\t51820\toff\n'
printf 'wg0\tPEERKEY1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=\t(none)\t117.136.1.2:41820\t10.8.0.2/32\t$((NOW-30))\t$((1000000 + T*50000))\t$((5000000 + T*200000))\t25\n'
printf 'wg0\tPEERKEY2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=\t(none)\t(none)\t10.8.0.3/32,192.168.10.0/24\t0\t0\t0\toff\n'
X
chmod +x "$B/nft" "$B/wg"
