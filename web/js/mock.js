/* openwrt-pulse 模拟数据源：生成与路由器采集器 (/cgi-bin/pulse) 完全相同结构的快照，
 * 计数器是累计字节数，前端用相邻两次快照求差得到速率，所以模拟模式也走真实的计算路径。 */
(function () {
  'use strict';
  let seed = 20261011;
  const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
  const gauss = () => { let u = 0, v = 0; while (!u) u = rnd(); while (!v) v = rnd(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };
  const MB = 1e6 / 8; // 1 Mbps = 125000 B/s

  // 基础画像：base = 平时下行 Mbps，up = 上行占比，burst = 突发时下行 Mbps，p = 每秒进入突发的概率
  const PROFILES = [
    { name: '书房台式机', mac: '3c:7c:3f:1a:22:01', ip: 41, link: 'wired', base: 3.5, up: 0.25, burst: 180, p: 0.012, conns: 120 },
    { name: 'NAS-DS920', mac: '00:11:32:aa:5e:02', ip: 10, link: 'wired', base: 1.2, up: 2.2, burst: 60, p: 0.008, conns: 60 },
    { name: 'PS5', mac: '78:c8:81:0b:4d:03', ip: 52, link: 'wired', base: 0.3, up: 0.3, burst: 260, p: 0.006, conns: 18 },
    { name: '小米电视', mac: 'a4:39:b3:7e:11:04', ip: 66, link: 'wired', base: 14, up: 0.04, burst: 32, p: 0.01, conns: 25 },
    { name: '打印机', mac: '30:05:5c:21:9a:05', ip: 20, link: 'wired', base: 0.01, up: 1, burst: 0.4, p: 0.004, conns: 2 },
    { name: '家用摄像头', mac: '64:90:c1:aa:33:06', ip: 31, link: 'wired', base: 0.08, up: 30, burst: 0.2, p: 0.01, conns: 4 },
    { name: 'HomeAssistant', mac: '52:54:00:12:34:07', ip: 5, link: 'wired', base: 0.05, up: 0.6, burst: 2, p: 0.005, conns: 9 },
    { name: 'iPhone 15', mac: 'f2:1a:9c:44:01:11', ip: 101, link: 'wifi', band: '5G', base: 2.2, up: 0.18, burst: 85, p: 0.014, conns: 70, sig: -48 },
    { name: 'MacBook Air', mac: 'a8:5c:2c:61:7f:12', ip: 102, link: 'wifi', band: '5G', base: 4.8, up: 0.3, burst: 210, p: 0.01, conns: 150, sig: -55 },
    { name: 'iPad', mac: 'de:21:7a:33:ee:13', ip: 103, link: 'wifi', band: '5G', base: 6.5, up: 0.06, burst: 40, p: 0.008, conns: 30, sig: -61 },
    { name: '小米音箱', mac: '50:ec:50:1d:28:14', ip: 104, link: 'wifi', band: '2.4G', base: 0.15, up: 0.2, burst: 0.9, p: 0.006, conns: 6, sig: -63 },
    { name: '扫地机器人', mac: '50:ec:50:9f:02:15', ip: 105, link: 'wifi', band: '2.4G', base: 0.02, up: 1.4, burst: 0.3, p: 0.004, conns: 3, sig: -70 },
    { name: 'Switch', mac: '98:41:5c:aa:0c:16', ip: 106, link: 'wifi', band: '5G', base: 0.05, up: 0.4, burst: 95, p: 0.004, conns: 8, sig: -58 },
    { name: '老婆的 Pixel', mac: '3a:9e:11:7c:5d:17', ip: 107, link: 'wifi', band: '5G', base: 1.6, up: 0.2, burst: 50, p: 0.01, conns: 55, sig: -52 },
    { name: 'Kindle', mac: '74:c2:46:01:aa:18', ip: 108, link: 'wifi', band: '2.4G', base: 0.0, up: 1, burst: 3, p: 0.003, conns: 1, sig: -67 }
  ];
  // 稍后才加入的设备（用来演示「新设备加入」与「DHCP 租约」事件）
  const LATE = [
    { name: '访客-iPhone', mac: '6e:44:b0:12:9a:21', ip: 141, link: 'wifi', band: '5G', base: 1.8, up: 0.2, burst: 30, p: 0.01, conns: 40, sig: -66, joinAt: 25 },
    { name: 'Galaxy-Tab', mac: 'b6:3d:7a:90:01:22', ip: 142, link: 'wifi', band: '2.4G', base: 0.9, up: 0.1, burst: 12, p: 0.01, conns: 20, sig: -71, joinAt: 150 },
    { name: 'raspberrypi', mac: 'dc:a6:32:5b:7c:23', ip: 143, link: 'wired', base: 0.2, up: 0.5, burst: 8, p: 0.01, conns: 12, joinAt: 260 }
  ];
  const WG = [
    { name: '我的手机（外出）', pub: 'K3vQ9a…', endpoint: '117.136.x.x:41820', allowed: '10.8.0.2/32', base: 0.6, active: true },
    { name: '公司笔记本', pub: 'pX7mR2…', endpoint: '58.33.x.x:51820', allowed: '10.8.0.3/32', base: 1.4, active: true },
    { name: '爸妈家路由器', pub: 'Zt0bL8…', endpoint: '183.6.x.x:51820', allowed: '10.8.0.4/32, 192.168.10.0/24', base: 0.25, active: true },
    { name: '云服务器 VPS', pub: 'Qe5nW1…', endpoint: '203.0.113.x:51820', allowed: '10.8.0.10/32', base: 0.4, active: true },
    { name: '旧平板', pub: 'aa4Hc6…', endpoint: '(none)', allowed: '10.8.0.5/32', base: 0, active: false }
  ];

  function makeDev(p, now) {
    return Object.assign({}, p, { rx: 1e9 * (0.5 + rnd() * 20), tx: 1e8 * (0.5 + rnd() * 20), level: p.base, burstLeft: 0,
      leaseStart: now, curConns: p.conns });
  }

  function MockSource() {
    this.t = 0; // 模拟经过的秒数
    this.devs = []; this.wg = []; this.ct = 1800; this.extraWan = { rx: 3.2e11, tx: 4.1e10 };
    this.lanIf = { rx: 9e11, tx: 6e11 };
  }
  MockSource.prototype.init = function (startMs) {
    this.start = startMs; this.devs = PROFILES.map(p => makeDev(p, startMs));
    this.late = LATE.map(p => Object.assign({}, p));
    this.wg = WG.map(w => Object.assign({}, w, { rx: 2e9 * rnd(), tx: 5e8 * rnd(), hs: w.active ? startMs / 1000 - 20 - rnd() * 90 : startMs / 1000 - 86400 * 9 }));
    this.wanBytes = { rx: 4.2e12, tx: 7.9e11 };
  };
  // 推进 dt 秒，返回一个快照（ts 为毫秒）
  MockSource.prototype.step = function (tsMs, dt, full) {
    if (!this.devs.length) this.init(tsMs - 1000);
    this.t += dt;
    // 新设备加入
    this.late = this.late.filter(p => { if (this.t >= p.joinAt) { this.devs.push(makeDev(p, tsMs)); this.devs[this.devs.length - 1].rx = 1e5; this.devs[this.devs.length - 1].tx = 2e4; return false; } return true; });
    // 偶尔有设备离线再回来
    let wanRx = 0, wanTx = 0;
    const hour = new Date(tsMs).getHours();
    const dayK = (hour >= 19 && hour <= 23) ? 1.25 : (hour < 7 ? 0.45 : 1);
    this.devs.forEach(d => {
      if (d.burstLeft > 0) { d.burstLeft -= dt; d.level += (d.burst * (0.8 + 0.4 * rnd()) - d.level) * 0.5; }
      else {
        if (rnd() < d.p * dt) d.burstLeft = 4 + rnd() * 14;
        d.level += (d.base * dayK - d.level) * 0.35 + gauss() * d.base * 0.12;
      }
      if (d.level < 0) d.level = d.base * 0.1 * rnd();
      const down = d.level, up = Math.max(0, d.level * d.up * (0.85 + 0.3 * rnd()));
      d.rx += down * MB * dt; d.tx += up * MB * dt;
      wanRx += down; wanTx += up;
      const targetC = d.conns * (d.burstLeft > 0 ? 2.4 : 1) * (0.9 + 0.2 * rnd());
      d.curConns += (targetC - d.curConns) * 0.4;
    });
    // WireGuard
    let wgRx = 0, wgTx = 0;
    this.wg.forEach(w => {
      if (!w.active) return;
      const lv = Math.max(0, w.base * (0.6 + 0.8 * rnd()) + (rnd() < 0.02 ? 15 * rnd() : 0));
      w.rx += lv * 0.35 * MB * dt; w.tx += lv * MB * dt; wgRx += lv * 0.35; wgTx += lv;
      if (tsMs / 1000 - w.hs > 120 + rnd() * 20) w.hs = tsMs / 1000 - rnd() * 3;
    });
    // 公司笔记本 第 90~300 秒握手停止（约第 150 秒触发「握手超时」，第 300 秒重连）
    const lap = this.wg[1];
    if (this.t > 90 && this.t < 300) lap.hs = Math.min(lap.hs, this.start / 1000 - 30);
    if (this.t >= 300 && this.t < 301) lap.hs = tsMs / 1000;

    const ovh = 1.03;
    this.wanBytes.rx += (wanRx * ovh + wgRx + 0.05) * MB * dt;
    this.wanBytes.tx += (wanTx * ovh + wgTx + 0.03) * MB * dt;
    // 连接数：设备之和 + 噪声，偶尔激增
    const baseCt = this.devs.reduce((s, d) => s + d.curConns, 0) * 1.9 + 120;
    if (rnd() < 0.012) this.ct = baseCt * (1.5 + rnd() * 0.6);
    else this.ct += (baseCt - this.ct) * 0.25 + gauss() * 15;
    const ct = Math.round(Math.max(50, this.ct));

    const devices = this.devs.map(d => ({
      mac: d.mac, ip: '192.168.1.' + d.ip, ip6: [], name: d.name, link: d.link,
      radio: d.link === 'wifi' ? (d.band === '5G' ? 'phy1-ap0' : 'phy0-ap0') : '', band: d.band || '',
      signal: d.sig ? Math.round(d.sig + gauss() * 1.5) : null, online: true,
      rx_bytes: Math.round(d.rx), tx_bytes: Math.round(d.tx), conns: full ? Math.round(d.curConns) : undefined
    }));
    const leases = this.devs.map(d => ({ mac: d.mac, ip: '192.168.1.' + d.ip, name: d.name, expires: Math.round((d.leaseStart / 1000 + 43200) - tsMs / 1000) }));
    const sumIf = (arr, k) => arr.reduce((s, d) => s + d[k], 0);
    const wifi5 = this.devs.filter(d => d.link === 'wifi' && d.band === '5G'), wifi2 = this.devs.filter(d => d.link === 'wifi' && d.band !== '5G');
    const lanRx = sumIf(this.devs, 'tx'), lanTx = sumIf(this.devs, 'rx');
    const wgAll = { rx: sumIf(this.wg, 'rx'), tx: sumIf(this.wg, 'tx') };
    return {
      v: 1, ts: tsMs, full: !!full, mock: true, counter_source: 'nft',
      router: { hostname: 'OpenWrt', model: 'Redmi AX6000（模拟）', release: 'OpenWrt 24.10.3', uptime: 864000 + Math.round(this.t),
        load: [0.18 + rnd() * 0.1, 0.21, 0.19], mem_total: 512 * 1048576, mem_avail: (318 + rnd() * 6) * 1048576, lan_ip: '192.168.1.1', lan_cidr: '192.168.1.0/24' },
      wan: { iface: 'wan', device: 'pppoe-wan', proto: 'pppoe', up: true, ipv4: '113.87.x.x', ipv6: '240e:3b0:xxxx::1', rx_bytes: Math.round(this.wanBytes.rx), tx_bytes: Math.round(this.wanBytes.tx) },
      interfaces: [
        { name: 'wan', device: 'pppoe-wan', kind: 'wan', proto: 'pppoe', up: true, ipv4: '113.87.x.x', rx_bytes: Math.round(this.wanBytes.rx), tx_bytes: Math.round(this.wanBytes.tx), speed: '1000F' },
        { name: 'lan', device: 'br-lan', kind: 'lan', proto: 'static', up: true, ipv4: '192.168.1.1/24', rx_bytes: Math.round(lanRx), tx_bytes: Math.round(lanTx), speed: '' },
        { name: 'wg0', device: 'wg0', kind: 'wg', proto: 'wireguard', up: true, ipv4: '10.8.0.1/24', rx_bytes: Math.round(wgAll.rx), tx_bytes: Math.round(wgAll.tx), speed: '' },
        { name: 'wifi 5G', device: 'phy1-ap0', kind: 'wifi', proto: 'ap', up: true, ipv4: '', rx_bytes: Math.round(sumIf(wifi5, 'tx')), tx_bytes: Math.round(sumIf(wifi5, 'rx')), speed: 'ch149' },
        { name: 'wifi 2.4G', device: 'phy0-ap0', kind: 'wifi', proto: 'ap', up: true, ipv4: '', rx_bytes: Math.round(sumIf(wifi2, 'tx')), tx_bytes: Math.round(sumIf(wifi2, 'rx')), speed: 'ch6' },
        { name: 'guest', device: 'br-guest', kind: 'other', proto: 'static', up: false, ipv4: '192.168.3.1/24', rx_bytes: 0, tx_bytes: 0, speed: '' }
      ],
      devices, leases,
      wg: this.wg.map(w => ({ iface: 'wg0', pubkey: w.pub, name: w.name, endpoint: w.endpoint, allowed: w.allowed, handshake: Math.round(w.hs), rx_bytes: Math.round(w.rx), tx_bytes: Math.round(w.tx) })),
      conntrack: { count: ct, max: 16384 }
    };
  };
  window.PulseMock = MockSource;
})();
