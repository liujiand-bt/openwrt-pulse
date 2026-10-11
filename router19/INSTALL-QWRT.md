# openwrt-pulse 安装指南 · 京东云 AX1800 Pro（QWRT R24.5.1 / OpenWrt 19.07）

> 本文件属于 [openwrt-pulse](../README.md) 仓库的 `router19/`（Lua 采集器）。
> 现代 OpenWrt（23.05+）请用根目录 README 里的 `router/` 安装步骤。

这台机器的情况：IPQ6018、内核 4.4.60、**没有 ucode**、有 Lua（LuCI 用的就是 Lua）、开着高通 **NSS + ECM 硬件加速**、overlay 只剩约 435 KB。
所以这里用 **Lua 版采集器**：路由器上只放采集器 + 诊断脚本 + 配置，**约 31 KB**；网页（前端）放在你自己的电脑上打开。

> 下面的 `192.168.1.1` 换成你路由器的实际 LAN 地址。所有命令在路由器上用 `root` 执行。

---

## 0. 准备

下载安装包：https://github.com/liujiand-bt/openwrt-pulse/releases/latest/download/pulse-qwrt.tar.gz（每个版本的 `SHA256SUMS` 在 GitHub Releases 页面）。

在电脑上解压 `pulse-qwrt.tar.gz`，得到 `pulse-qwrt/` 文件夹：

```
pulse-qwrt/
  pulse            采集器（Lua CGI，约 21 KB）
  diag.sh          诊断脚本
  server.sh        临时小网站（tmp 模式用）
  pulse.config     配置模板
  99-pulse.conf    开机打开 conntrack 字节统计
  install.sh / uninstall.sh
  web/             前端网页（在电脑上双击 web/index.html）
```

## 1. 上传到路由器

**方法 0：路由器直接下载**（19.07 的 wget 可能不支持 HTTPS，或者证书太旧；失败就用下面的方法 A/B）

```bash
cd /tmp && wget -O pulse-qwrt.tar.gz https://github.com/liujiand-bt/openwrt-pulse/releases/latest/download/pulse-qwrt.tar.gz
# 证书报错：wget --no-check-certificate ...  或  curl -fkL -o pulse-qwrt.tar.gz https://github.com/liujiand-bt/openwrt-pulse/releases/latest/download/pulse-qwrt.tar.gz
```

**方法 A：scp**（macOS / Linux / Windows 10+ 自带的 OpenSSH 都可以）

```bash
scp -O pulse-qwrt.tar.gz root@192.168.1.1:/tmp/
```

`-O` 表示用老式 scp 协议。路由器上的 dropbear 不支持 SFTP，新版 OpenSSH 默认走 SFTP，不加 `-O` 会报 `sftp-server: not found` 之类的错。

**方法 B：不用 scp，直接用 ssh 管道传**（macOS / Linux / Git Bash；Windows PowerShell 别用这种，会破坏二进制文件）

```bash
cat pulse-qwrt.tar.gz | ssh root@192.168.1.1 'cat > /tmp/pulse-qwrt.tar.gz'
```

如果 ssh 报 `no matching host key type`，加上 `-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa`。

然后登录路由器并解压：

```bash
ssh root@192.168.1.1
cd /tmp && tar xzf pulse-qwrt.tar.gz      # 不支持 z 的话：gunzip -c pulse-qwrt.tar.gz | tar x
```

## 2. 先跑一次诊断（推荐，什么都不安装）

```bash
sh /tmp/pulse-qwrt/diag.sh
```

它会检查：lua 和 ubus / iwinfo / uci 模块、uhttpd、`/proc/net/nf_conntrack`、`nf_conntrack_acct`、ECM / NSS、无线客户端能不能读到、WireGuard、IPv6 邻居，最后做一个 **5 秒对比**（WAN 接口速率 vs conntrack 统计到的速率）。跑诊断的时候最好在某台设备上测速或下载大文件，对比才有意义。

输出里的 MAC 后半段和公网 IP 已经自动打码，可以直接发给我们。**一键把诊断结果存成文件**（在电脑上执行）：

```bash
ssh root@192.168.1.1 'sh /tmp/pulse-qwrt/diag.sh' > pulse-diag.txt
```

装好以后路径会变成 `/usr/share/pulse/diag.sh`：

```bash
ssh root@192.168.1.1 'sh /usr/share/pulse/diag.sh' > pulse-diag.txt
```

## 3A. 临时安装试用（不写闪存，重启就没了）

```bash
sh /tmp/pulse-qwrt/install.sh tmp
```

它会把采集器和网页都放进 `/tmp/pulse`（内存里），并在 `http://192.168.1.1:8088/` 起一个只监听内网地址的小网站。命令最后会打印带口令的地址，直接在电脑浏览器里打开就行。停止：`sh /tmp/pulse/server.sh stop`。

## 3B. 常驻安装

```bash
sh /tmp/pulse-qwrt/install.sh
```

装完后各文件的位置：

| 文件 | 位置 | 大小 |
|---|---|---|
| 采集器 | `/www/cgi-bin/pulse`（由路由器自带的 uhttpd 执行） | 约 21 KB |
| 诊断 / 临时网站脚本 | `/usr/share/pulse/diag.sh`、`server.sh` | 约 9.5 KB |
| 配置 | `/etc/config/pulse`（口令自动生成） | 约 0.9 KB |
| 开机设置 | `/etc/sysctl.d/99-pulse.conf`（`nf_conntrack_acct=1`） | 34 B |
| 运行状态 | `/tmp/pulse/`（内存，每秒更新，不写闪存） | 几十到几百 KB |

脚本最后会打印口令。以后忘了可以用 `uci get pulse.main.token` 查看。

**装完建议重启一次路由器**：`nf_conntrack_acct` 只对之后新建的连接生效，重启后所有连接都会带上字节统计。

## 4. 用 curl 测采集器

在电脑或路由器上：

```bash
curl -s 'http://192.168.1.1/cgi-bin/pulse?token=你的口令' | head -c 400
```

正常会看到以 `{"interfaces":[...` 开头的 JSON，里面有 `"collector":"lua"`、`"counter_source":"conntrack"`。
- 口令不对会返回 `403`。
- 返回 404 说明 uhttpd 没有开 `/cgi-bin`，或者固件用的是别的 web 服务器。这时用 `sh /usr/share/pulse/server.sh start` 起一个独立的小网站（端口 8088），地址换成 `http://192.168.1.1:8088/cgi-bin/pulse`。不过 server.sh 只读 `/tmp/pulse/www`，需要先执行一次 `install.sh tmp`。

## 5. 在电脑上打开面板

1. 双击 `pulse-qwrt/web/index.html`（Chrome / Edge / Firefox 都可以）。
2. 弹出「连接路由器」：地址填 `http://192.168.1.1/cgi-bin/pulse`，口令填上一步的口令，点「连接路由器」。
3. 地址和口令只保存在这台电脑的浏览器里。想换路由器，点右上角「连接路由器」重新填。

也可以把这两项直接写在网址里：`index.html?endpoint=http://192.168.1.1/cgi-bin/pulse&token=口令`

页面顶部出现黄色提示「检测到高通 ECM/NSS 硬件加速…」是正常的，见下一节。

## 6. 准确性说明（NSS / ECM 硬件加速）

- **WAN 总速率**取自接口计数器（`/proc/net/dev`）。NSS 会把加速流量回写到网卡统计里，一般是准的。如果诊断显示 `pppoe-wan` 明显比底层网口低，执行 `uci set pulse.main.wan_stats_dev=eth0; uci commit pulse` 改用底层网口统计（`eth0` 换成诊断里显示的那个口）。
- **每台设备的速率**来自 conntrack。原理：硬件加速后，包不再经过 Linux 的 netfilter，所以 iptables / nft 这类规则计数会严重偏低。但高通 ECM 会定期向 NSS 固件请求每条连接的统计，再用 `atomic64_add` 把字节数加回这条连接的 conntrack 计数（ECM 源码 `ecm_nss_ipv4.c` 里的 conn sync，请求周期 `ECM_NSS_IPV4_STATS_SYNC_PERIOD = 1000 ms`）。前提是 `nf_conntrack_acct=1`，否则 conntrack 上没有计数器可加。
  - 所以总量基本是准的，但**速率会滞后 1–3 秒、有跳动**。面板检测到 ECM 后会自动按 3 秒窗口平滑。网址加 `&smooth=1` 可以关掉平滑。
  - 连接很多时（上千条），ECM 一轮同步要分好几批，延迟会更大。
  - 连接结束前最后不到 1 秒的流量会丢掉。采集器在 `/tmp/pulse/ct.state` 记下每条连接上一次的字节数，只累加差值，所以连接结束不会让数字倒退。
  - 开启 acct 之前就建立的连接没有计数器，需要重连（或重启路由器）后才会被统计到。
- **内网设备之间的流量**（比如电脑往 NAS 拷文件）走交换芯片或网桥，不经过 conntrack，**不会统计**。面板上只有设备进出外网的流量（以及 WireGuard 访问内网的流量）。
- **IPv6**：如果 `ip -6 neigh` 能用（诊断里「IPv6 邻居」大于 0），IPv6 连接会按邻居表算到对应设备上，否则只计入 WAN 总量。
- 想试 iptables 计数的话（只在关掉硬件加速时才准）：`uci set pulse.main.counters=iptables; uci commit pulse`。采集器会在 mangle 表建一条 `pulse` 链，每个 IP 两条只计数的规则。开着 ECM 时数字会严重偏低，诊断脚本会提醒。
- 采集器每秒要扫一遍连接跟踪表。按 PC 上的测试估算，5000 条连接时在这颗 A53 上每次大约 0.15–0.3 秒 CPU；平时家用几百到两千条，负担很小。如果觉得高，可以把电脑端 `web/js/config.js` 里的 `intervalMs` 改成 2000。

## 7. 安全

- 只在内网用。**不要**给 80 或 8088 做端口转发；要在外面看，先连回家里的 WireGuard。
- 口令是共享密钥，走明文 HTTP，防的是家里其他人随手打开，扛不住有针对性的攻击。
- 采集器只读：不改路由和防火墙（只有手动设成 `counters=iptables` 时，才会建那条只计数的 `pulse` 链）。WireGuard 私钥不会输出。

## 8. 卸载

```bash
sh /tmp/pulse-qwrt/uninstall.sh          # 如果 /tmp 里的安装包已经没了，重新上传后再执行
sh /tmp/pulse-qwrt/uninstall.sh --all    # 连 /etc/config/pulse 一起删
```

会删掉 `/www/cgi-bin/pulse`、`/usr/share/pulse`、`/etc/sysctl.d/99-pulse.conf`、`/tmp/pulse`，停掉 8088 小网站，并删除 iptables 的 `pulse` 链（如果建过）。
`nf_conntrack_acct` 当场仍是 1，重启后恢复固件默认值。
