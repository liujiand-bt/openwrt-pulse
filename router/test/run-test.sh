#!/bin/sh
# 用自编译的 ucode 离线运行采集器：两次快照（相隔"1 秒"），检查结构与关键字段
D=$(cd "$(dirname "$0")" && pwd); U=${UCODE_BUILD:-/tmp/ucode-src/build}
run() { "$D/make-fixture.sh" "$1" >/dev/null; PATH="$D/bin:$PATH" PULSE_ROOT="$D/root" QUERY_STRING="full=1" LD_LIBRARY_PATH="$U" \
  "$U/ucode" -L "$U/*.so" -L "$D/lib/*.uc" -S "$D/../files/www/cgi-bin/pulse"; }
run 0 > "$D/out0.txt"; run 1 > "$D/out1.txt"
sed '1,/^\r$/d' "$D/out1.txt" > "$D/out1.json"
if grep -q PRIVATEKEY "$D/out1.txt"; then echo "FAIL: private key leaked"; exit 1; fi
python3 - "$D" <<'P'
import json,sys,re
d=sys.argv[1]
raw0=open(d+'/out0.txt',newline='').read(); raw1=open(d+'/out1.txt',newline='').read()
h,b0=raw0.split('\r\n\r\n',1); _,b1=raw1.split('\r\n\r\n',1)
assert 'application/json' in h, h
a=json.loads(b0); b=json.loads(b1)
for k in ['v','ts','router','wan','interfaces','devices','leases','wg','conntrack','counter_source']: assert k in b, k
assert b['counter_source']=='nft', b['counter_source']
dev={x['mac']:x for x in b['devices']}
assert dev['00:11:32:aa:5e:02']['name']=='NAS-DS920'
assert dev['a8:5c:2c:61:7f:12']['link']=='wifi' and dev['a8:5c:2c:61:7f:12']['band']=='5G'
assert 'f2:1a:9c:44:01:11' in dev   # 只在无线关联表里的设备
assert dev['3c:7c:3f:1a:22:01']['conns']==2
assert b['wg'][0]['name']=='我的手机' and 'PRIVATE' not in json.dumps(b)
assert b['router']['lan_cidr']=='192.168.1.0/24', b['router']['lan_cidr']
assert b['wan']['device']=='pppoe-wan' and b['wan']['ipv6']=='240e:3b0::1234'
da={x['mac']:x for x in a['devices']}
r=(dev['3c:7c:3f:1a:22:01']['rx_bytes']-da['3c:7c:3f:1a:22:01']['rx_bytes'])*8/1e6
print('OK  devices=%d  wg=%d  ifaces=%d  collect_ms=%s  书房台式机 rate(1s)=%.1f Mbps'%(len(b['devices']),len(b['wg']),len(b['interfaces']),b['collect_ms'],r))
print(json.dumps(b,ensure_ascii=False,indent=1)[:1500])
P
