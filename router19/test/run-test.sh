#!/bin/sh
# 用 Lua 5.1 离线跑 19.07 采集器：3 次请求（T=0,1,2），检查格式、字段、差值累加逻辑
D=$(cd "$(dirname "$0")" && pwd); C=${PULSE_COLLECTOR_PATH:-$D/../files/www/cgi-bin/pulse}
LUA=${LUA:-lua5.1}
S=$D/state; rm -rf "$S"
run() { "$D/make-fixture.sh" "$1" >/dev/null
  env -i PATH="$D/bin:/usr/bin:/bin" PULSE_ROOT="$D/root" PULSE_STATE="$S" PULSE_FAKE_MONO=$((360000000 + $1*1000)) \
      QUERY_STRING="$2" HTTP_X_PULSE_TOKEN="$3" PULSE_TEST_TOKEN="$4" LUA_PATH="${LUA_PATH_EXTRA:-}" $LUA "$C"; }
run 0 > "$D/out0.txt"; run 1 > "$D/out1.txt"; run 2 > "$D/out2.txt"
grep -q PRIVATEKEY "$D"/out*.txt && { echo "FAIL: 私钥泄露"; exit 1; }
python3 - "$D" <<'P'
import json,sys
d=sys.argv[1]
def body(n):
    raw=open(f'{d}/out{n}.txt',newline='').read(); h,b=raw.split('\r\n\r\n',1); assert 'application/json' in h; return json.loads(b)
a,b,c=body(0),body(1),body(2)
assert c['collector']=='lua' and c['counter_source']=='conntrack', c['counter_source']
dv=lambda s:{x['mac']:x for x in s['devices']}
A,B,C=dv(a),dv(b),dv(c)
desk='3c:7c:3f:1a:22:01'; mac='a8:5c:2c:61:7f:12'; nas='00:11:32:aa:5e:02'; spk='50:ec:50:1d:28:14'
assert A[desk]['rx_bytes']==0                                  # 首次只建立基线
assert B[desk]['rx_bytes']==3000000 and B[desk]['tx_bytes']==400000, B[desk]
assert B[mac]['rx_bytes']==1500000+500000, B[mac]             # IPv4 QUIC + IPv6
assert B[nas]['tx_bytes']==2000000 and B[nas]['rx_bytes']==20000, B[nas]   # 端口转发方向
assert C[desk]['rx_bytes']==6000000                            # 单调累加
assert C[spk]['rx_bytes']==B[spk]['rx_bytes']+50000, (B[spk],C[spk])        # 旧连接结束、新连接出现
assert B[nas]['name']=='NAS-DS920' and B[desk]['name']=='DESKTOP-ABC'
assert B[mac]['link']=='wifi' and B[mac]['band']=='5G' and B[mac]['signal']==-55
assert B[spk]['link']=='wifi' and B[spk]['band']=='2.4G', B[spk]
pc='04:d3:b0:7b:2b:27'
assert pc in B, sorted(B)
assert B[pc]['link']=='wifi', B[pc]          # ARP 有线口 + 无线 assoc → 仍算无线
assert B[pc]['band']=='2.4G' and B[pc]['name']=='DESKTOP-ASLUHVI', B[pc]
assert B[pc]['radio']=='ath0'
assert '00:00:00:50:3d:b5' not in B, 'mangled iwinfo MAC must not become a ghost device'
assert 'f2:1a:9c:44:01:11' in B
assert B[desk]['conns']==1 and B[nas]['conns']==1
assert c['wg'][0]['name']=='我的手机' and c['wg'][0]['handshake']>0
assert c['router']['lan_cidr']=='192.168.1.0/24' and c['wan']['device']=='pppoe-wan' and c['wan']['ipv6']=='240e:3b0:ffff::1'
assert c['hints']['accel']=='ecm' and c['hints']['smooth']==3 and any('ECM' in w for w in c['warnings'])
assert {i['device'] for i in c['interfaces']} >= {'br-lan','pppoe-wan','wg0','ath0','ath1'}
dt=(c['mono']-b['mono'])/1000
print('OK  Lua 采集器：devices=%d ifaces=%d wg=%d collect_ms=%s  书房台式机下行 %.1f Mbps'%(len(c['devices']),len(c['interfaces']),len(c['wg']),c['collect_ms'],(C[desk]['rx_bytes']-B[desk]['rx_bytes'])*8/1e6/dt))
P

# ---- 第二轮：有 libubus-lua / libiwinfo-lua / libuci-lua / luci.jsonc 时 ----
if [ -z "$LUA_PATH_EXTRA" ]; then
  LUA_PATH_EXTRA="$D/lualib/?.lua;;" "$0" && echo "OK  Lua 绑定路径（ubus/iwinfo/uci/jsonc）"
  # 缓存：同一时刻的第二个请求直接返回上次结果
  "$D/make-fixture.sh" 5 >/dev/null; S=$D/state
  for i in 1 2; do env -i PATH="$D/bin:/usr/bin:/bin" PULSE_ROOT="$D/root" PULSE_STATE="$S" PULSE_FAKE_MONO=999000 $LUA "$C" > "$D/cache$i.txt"; done
  cmp -s "$D/cache1.txt" "$D/cache2.txt" && echo "OK  700ms 内重复请求走缓存"
  # 口令
  env -i PATH="$D/bin:/usr/bin:/bin" PULSE_ROOT="$D/root" PULSE_STATE="$D/st2" PULSE_TEST_TOKEN=s3cret $LUA "$C" | head -1 | grep -q "403" && echo "OK  口令错误返回 403"
  env -i PATH="$D/bin:/usr/bin:/bin" PULSE_ROOT="$D/root" PULSE_STATE="$D/st2" PULSE_TEST_TOKEN=s3cret HTTP_X_PULSE_TOKEN=s3cret $LUA "$C" | grep -q '"collector":"lua"' && echo "OK  口令正确返回数据"
  # acct 关闭
  ACCT=0 "$D/make-fixture.sh" 6 >/dev/null
  env -i PATH="$D/bin:/usr/bin:/bin" PULSE_ROOT="$D/root" PULSE_STATE="$D/st3" $LUA "$C" | grep -q 'nf_conntrack_acct=0' && echo "OK  acct=0 时给出警告"
  rm -rf "$D/st2" "$D/st3" "$D"/cache*.txt

# ---- WiFi 分类回归：iwinfo 返回错位 MAC、wlanconfig 返回真 MAC ----
"$D/make-fixture.sh" 0 >/dev/null
python3 - "$D" <<'W'
import json,sys,os,subprocess
d=sys.argv[1]
env=dict(os.environ)
env.update(PATH=d+"/bin:/usr/bin:/bin", PULSE_ROOT=d+"/root", PULSE_STATE=d+"/state-wifi",
           LUA_PATH=d+"/lualib/?.lua;;", PULSE_FAKE_MONO="1000")
raw=subprocess.check_output(["lua5.1", os.environ.get("PULSE_COLLECTOR_PATH", d+"/../files/www/cgi-bin/pulse")], env=env)
body=raw.split(b"\r\n\r\n",1)[1]
j=json.loads(body)
by={x["mac"]:x for x in j["devices"]}
pc="04:d3:b0:7b:2b:27"
assert pc in by and by[pc]["link"]=="wifi" and by[pc]["band"]=="2.4G" and by[pc]["name"]=="DESKTOP-ASLUHVI", by.get(pc)
assert "00:00:00:50:3d:b5" not in by
assert by["50:ec:50:1d:28:14"]["link"]=="wifi"
print("OK  WiFi 分类：错位 iwinfo MAC 被丢弃，真 MAC 标为无线 + DHCP 名")
W
rm -rf "$D/state-wifi"

fi
