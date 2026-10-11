/* openwrt-pulse 状态与事件计算：输入累计计数器快照，输出速率、峰值、历史、事件。
 * 与数据源无关（模拟 / 路由器采集器 共用）。 */
(function () {
  'use strict';
  const HIST = 90; // 保留 90 个点（约 90 秒）用于迷你曲线

  function Pulse(cfg) {
    this.cfg = cfg; this.prev = null; this.cur = null;
    this.rates = { wan: { rx: 0, tx: 0 }, dev: {}, wg: {}, ifc: {} };
    this.hist = { wanRx: [], wanTx: [], dev: {}, ct: [] };
    this.peak = { rx: 0, tx: 0, rxAt: 0, txAt: 0 };
    this.ema = { dev: {}, wanRx: 0, wanTx: 0, ct: 0 };
    this.known = new Map();   // mac -> {firstSeen, name}
    this.leaseSeen = new Map();
    this.wgState = {};
    this.lastConns = {};      // mac -> conns（只在完整快照里有）
    this.events = [];
    this.ticks = 0;
    this.burstCool = {};
    this.smooth = 1;          // 速率按最近 N 个快照的跨度计算（ECM 加速时 N=3 更平滑）
    this.ring = [];
  }
  const mbps = (db, dt) => (db > 0 && dt > 0) ? db * 8 / dt / 1e6 : 0;
  const push = (arr, v) => { arr.push(v); if (arr.length > HIST) arr.shift(); };

  Pulse.prototype.event = function (ts, type, key, params) {
    this.events.unshift({ ts, type, key, params });
    if (this.events.length > 300) this.events.length = 300;
  };

  Pulse.prototype.ingest = function (s) {
    const cfg = this.cfg, prev = this.cur;
    this.prev = prev; this.cur = s; this.ticks++;
    const ts = s.ts;
    s.devices.forEach(d => { if (cfg.aliases && cfg.aliases[d.mac]) d.name = cfg.aliases[d.mac]; if (!d.name) d.name = d.ip || d.mac; });
    if (!prev) {
      // 第一帧：记住已有设备/租约，不报事件
      s.devices.forEach(d => this.known.set(d.mac, { first: ts, name: d.name }));
      s.leases.forEach(l => this.leaseSeen.set(l.mac + l.ip, ts));
      s.wg.forEach(w => { this.wgState[w.pubkey] = (ts / 1000 - w.handshake) < 180; });
      s.devices.forEach(d => { if (d.conns != null) this.lastConns[d.mac] = d.conns; });
      this.ema.ct = s.conntrack.count;
      this.ring.push(s);
      return;
    }
    const k = Math.max(1, Math.min(8, this.smooth | 0));
    const base = this.ring.length >= k ? this.ring[this.ring.length - k] : this.ring[0];
    this.ring.push(s); if (this.ring.length > 9) this.ring.shift();
    // 优先用路由器的单调时钟（/proc/uptime）计算时间差，不受系统时间跳变影响
    const span = (s.mono != null && base.mono != null && s.mono > base.mono) ? (s.mono - base.mono) : (s.ts - base.ts);
    const dt = Math.max(0.2, span / 1000);
    // WAN
    const r = this.rates;
    r.wan = { rx: mbps(s.wan.rx_bytes - base.wan.rx_bytes, dt), tx: mbps(s.wan.tx_bytes - base.wan.tx_bytes, dt) };
    push(this.hist.wanRx, r.wan.rx); push(this.hist.wanTx, r.wan.tx);
    if (r.wan.rx >= this.peak.rx) { this.peak.rx = r.wan.rx; this.peak.rxAt = ts; }
    if (r.wan.tx >= this.peak.tx) { this.peak.tx = r.wan.tx; this.peak.txAt = ts; }
    // 接口
    const pIf = {}; base.interfaces.forEach(i => pIf[i.device] = i);
    s.interfaces.forEach(i => { const p = pIf[i.device]; r.ifc[i.device] = p ? { rx: mbps(i.rx_bytes - p.rx_bytes, dt), tx: mbps(i.tx_bytes - p.tx_bytes, dt) } : { rx: 0, tx: 0 }; });
    // WireGuard
    const pWg = {}; base.wg.forEach(w => pWg[w.pubkey] = w);
    s.wg.forEach(w => {
      const p = pWg[w.pubkey];
      r.wg[w.pubkey] = p ? { rx: mbps(w.rx_bytes - p.rx_bytes, dt), tx: mbps(w.tx_bytes - p.tx_bytes, dt) } : { rx: 0, tx: 0 };
      const ok = w.handshake > 0 && (ts / 1000 - w.handshake) < 180;
      const was = this.wgState[w.pubkey];
      if (was === true && !ok) this.event(ts, 'wg', 'evWgDown', { name: w.name || w.pubkey });
      if (was === false && ok) this.event(ts, 'wg', 'evWgUp', { name: w.name || w.pubkey, ep: w.endpoint });
      this.wgState[w.pubkey] = ok;
    });
    // 设备
    const pDev = {}; base.devices.forEach(d => pDev[d.mac] = d);
    const seen = new Set();
    s.devices.forEach(d => {
      seen.add(d.mac);
      const p = pDev[d.mac];
      const rr = p ? { rx: mbps(d.rx_bytes - p.rx_bytes, dt), tx: mbps(d.tx_bytes - p.tx_bytes, dt) } : { rx: 0, tx: 0 };
      r.dev[d.mac] = rr;
      const h = this.hist.dev[d.mac] || (this.hist.dev[d.mac] = []);
      push(h, rr.rx + rr.tx);
      const tot = rr.rx + rr.tx;
      const e = this.ema.dev[d.mac] == null ? tot : this.ema.dev[d.mac];
      if (this.ticks > 8 && tot > cfg.burstMbps && tot > e * 3 && !(this.burstCool[d.mac] > ts)) {
        const dir = rr.rx >= rr.tx ? 'evBurstDown' : 'evBurstUp';
        this.event(ts, 'burst', dir, { name: d.name, v: Math.max(rr.rx, rr.tx), avg: e });
        this.burstCool[d.mac] = ts + 15000;
      }
      this.ema.dev[d.mac] = e + (tot - e) * 0.08;
      if (!this.known.has(d.mac)) {
        this.known.set(d.mac, { first: ts, name: d.name });
        this.event(ts, 'join', 'evJoin', { name: d.name, ip: d.ip, mac: d.mac, link: d.link, band: d.band });
      }
      if (d.conns != null) {
        const pc = this.lastConns[d.mac];
        if (pc != null && d.conns - pc > Math.max(200, pc * 1.5)) this.event(ts, 'conn', 'evDevConn', { name: d.name, a: pc, b: d.conns });
        this.lastConns[d.mac] = d.conns;
      }
    });
    prev.devices.forEach(d => { if (!seen.has(d.mac)) this.event(ts, 'leave', 'evLeave', { name: d.name, ip: d.ip }); });
    // DHCP 新租约
    s.leases.forEach(l => {
      const k = l.mac + l.ip;
      if (!this.leaseSeen.has(k)) { this.leaseSeen.set(k, ts); this.event(ts, 'dhcp', 'evLease', { ip: l.ip, name: l.name || l.mac, mac: l.mac }); }
    });
    // WAN 突发
    const wanTot = r.wan.rx;
    if (this.ticks <= 3) this.ema.wanRx = wanTot;
    if (this.ticks > 8 && wanTot > cfg.wanBurstMbps && wanTot > this.ema.wanRx * 2.5 && !(this.burstCool.wan > ts)) {
      this.event(ts, 'wan', 'evWanBurst', { v: wanTot, avg: this.ema.wanRx }); this.burstCool.wan = ts + 20000;
    }
    this.ema.wanRx += (wanTot - this.ema.wanRx) * 0.05;
    // 连接数激增
    const c = s.conntrack.count; push(this.hist.ct, c);
    if (this.ticks > 8 && c > this.ema.ct * (1 + cfg.connSpikePct / 100) && c - this.ema.ct > 200 && !(this.burstCool.ct > ts)) {
      this.event(ts, 'conn', 'evConnSpike', { a: Math.round(this.ema.ct), b: c }); this.burstCool.ct = ts + 15000;
    }
    this.ema.ct += (c - this.ema.ct) * 0.15;
  };

  window.PulseState = Pulse;
})();
