/* openwrt-pulse 流向图：纯 SVG，无依赖。结构变化时重建，其余每秒只更新文字和线宽，
 * 虚线流动由 requestAnimationFrame 驱动，速度与速率成对数关系。 */
(function () {
  'use strict';
  const NS = 'http://www.w3.org/2000/svg';
  const el = (tag, attrs, parent, text) => { const e = document.createElementNS(NS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; if (parent) parent.appendChild(e); return e; };
  const fmt = v => v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2);
  const curveH = (x1, y1, x2, y2) => { const mx = (x1 + x2) / 2; return `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`; };
  const curveV = (x1, y1, x2, y2) => { const my = (y1 + y2) / 2; return `M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}`; };
  const trunc = (s, n) => { let w = 0, out = ''; for (const ch of String(s)) { w += ch.charCodeAt(0) > 255 ? 2 : 1; if (w > n) return out + '…'; out += ch; } return out; };

  const PH = 24, GAP = 31;
  // 桌面布局（viewBox 1000×620）：左 WG/Internet，中 路由器→交换机→AP，右 设备列表
  function layoutDesktop(n) {
    const wgY = 50, wiredY = 50, wifiY = 336;
    return {
      vw: 1000, vh: 620, mode: 'd',
      inet: { x: 24, y: 302, w: 140, h: 56 }, router: { x: 272, y: 300, w: 196, h: 60 },
      sw: { x: 500, y: 130, w: 168, h: 56 }, ap: { x: 500, y: 410, w: 168, h: 56 },
      wg: { x: 24, y: wgY, w: 176, side: 'left' }, wired: { x: 736, y: wiredY, w: 240 }, wifi: { x: 736, y: wifiY, w: 240 },
      chart: { x: 24, y: 450, w: 410, h: 140 }
    };
  }
  // 窄屏布局（viewBox 400×H）：左列枢纽纵向串联，右列按组堆叠设备
  function layoutMobile(n) {
    const pX = 188, pW = 202, hX = 10, hW = 138;
    let y = 82;
    const grp = k => { const g = { x: pX, y: y + 22, w: pW }; y += 22 + Math.max(1, n[k]) * GAP + 22; return g; };
    const wg = grp('wg'), wired = grp('wired'), wifi = grp('wifi');
    const mid = (g, k, h) => Math.round(g.y + (Math.max(1, n[k]) * GAP - 7) / 2 - h / 2);
    return {
      vw: 400, vh: y, mode: 'm',
      inet: { x: hX, y: 14, w: hW, h: 50 }, router: { x: hX, y: Math.max(110, mid(wg, 'wg', 54)), w: hW, h: 54 },
      sw: { x: hX, y: mid(wired, 'wired', 52), w: hW, h: 52 }, ap: { x: hX, y: mid(wifi, 'wifi', 52), w: hW, h: 52 },
      wg: Object.assign(wg, { side: 'right' }), wired, wifi
    };
  }

  function Flow(svg, cfg, tip) {
    this.svg = svg; this.cfg = cfg; this.tip = tip; this.key = ''; this.edges = []; this.nodes = {};
    this.order = { wired: [], wifi: [], wg: [] }; this.orderAt = 0; this.lastT = 0;
    requestAnimationFrame(this.animate.bind(this));
  }

  Flow.prototype.pickOrder = function (S, s, force) {
    // 每 5 秒按平滑速率重排一次，避免列表每秒跳动
    if (!force && s.ts - this.orderAt < 5000 && this.order.ready) return;
    const ema = S.ema.dev, cfg = this.cfg;
    const byRate = (a, b) => (ema[b.mac] || 0) - (ema[a.mac] || 0);
    this.order.wired = s.devices.filter(d => d.link !== 'wifi').sort(byRate).slice(0, cfg.maxWired).map(d => d.mac);
    this.order.wifi = s.devices.filter(d => d.link === 'wifi').sort(byRate).slice(0, cfg.maxWireless).map(d => d.mac);
    const now = s.ts / 1000;
    this.order.wg = s.wg.slice().sort((a, b) => ((now - a.handshake < 180) ? 0 : 1) - ((now - b.handshake < 180) ? 0 : 1)).slice(0, cfg.maxWg).map(w => w.pubkey);
    this.order.ready = true; this.orderAt = s.ts;
  };

  Flow.prototype.box = function (g, b, title, sub, cls) {
    const grp = el('g', { class: 'node ' + (cls || '') }, g);
    el('rect', { x: b.x, y: b.y, width: b.w, height: b.h, rx: 7 }, grp);
    el('text', { x: b.x + b.w / 2, y: b.y + b.h / 2 - 4, class: 'n-title', 'text-anchor': 'middle' }, grp, title);
    const st = el('text', { x: b.x + b.w / 2, y: b.y + b.h / 2 + 14, class: 'n-sub mono', 'text-anchor': 'middle' }, grp, sub);
    return { g: grp, sub: st };
  };
  Flow.prototype.pill = function (g, x, y, w, name, kind) {
    const grp = el('g', { class: 'pill ' + kind }, g);
    el('rect', { x, y, width: w, height: PH, rx: 5 }, grp);
    const dot = el('circle', { cx: x + 11, cy: y + PH / 2, r: 3.6, class: 'pdot' }, grp);
    el('text', { x: x + 21, y: y + 16, class: 'p-name' }, grp, trunc(name, Math.floor((w - 74) / 6.3)));
    const val = el('text', { x: x + w - 9, y: y + 16, class: 'p-val mono', 'text-anchor': 'end' }, grp, '0.00');
    return { g: grp, dot, val };
  };
  Flow.prototype.edge = function (d, type, labelPos, anchor) {
    el('path', { d, class: 'e-track e-' + type }, this.eLayer);
    const p = el('path', { d, class: 'e-line e-' + type }, this.eLayer);
    const e = { p, type, rate: 0, off: 0 };
    if (labelPos) e.label = el('text', { x: labelPos[0], y: labelPos[1], class: 'e-label mono', 'text-anchor': anchor || 'middle' }, this.lLayer, '');
    this.edges.push(e); return e;
  };
  Flow.prototype.hover = function (g, fn) {
    g.addEventListener('mousemove', ev => this.tip.show(ev, fn()));
    g.addEventListener('mouseleave', () => this.tip.hide());
  };

  Flow.prototype.build = function (S, s) {
    const t = I18N.t, cfg = this.cfg, svg = this.svg;
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    this.edges = []; this.nodes = { dev: {}, wg: {} };
    const P = this.mobile ? layoutMobile({ wg: this.order.wg.length, wired: this.order.wired.length, wifi: this.order.wifi.length }) : layoutDesktop();
    this.P = P;
    svg.setAttribute('viewBox', `0 0 ${P.vw} ${P.vh}`);
    this.eLayer = el('g', {}, svg); this.lLayer = el('g', {}, svg); const nl = el('g', {}, svg);
    const R = P.router, I = P.inet, W = P.sw, A = P.ap, M = P.mode === 'm';
    const devMap = {}; s.devices.forEach(d => devMap[d.mac] = d);
    const wgMap = {}; s.wg.forEach(w => wgMap[w.pubkey] = w);
    const title = (g, k) => el('text', { x: g.x, y: g.y - 10, class: 'grp-title' }, nl, t(k));
    title(P.wg, 'wgPeers'); title(P.wired, 'wiredTop'); title(P.wifi, 'wifiTop');
    const rightMid = b => [b.x + b.w, b.y + b.h / 2];

    // WireGuard 对端 ↔ 路由器
    this.order.wg.forEach((k, i) => {
      const w = wgMap[k]; if (!w) return;
      const y = P.wg.y + i * GAP;
      const d = P.wg.side === 'left' ? curveH(P.wg.x + P.wg.w, y + PH / 2, R.x, R.y + 16 + i * 3) : curveH(R.x + R.w, R.y + 14 + i * 4, P.wg.x, y + PH / 2);
      const e = this.edge(d, 'wg');
      const p = this.pill(nl, P.wg.x, y, P.wg.w, w.name || w.pubkey, 'wg');
      this.nodes.wg[k] = { p, e };
      this.hover(p.g, () => this.tipWg(S, k));
    });
    // Internet → 路由器
    if (M) this.nodes.wanEdge = this.edge(curveV(I.x + I.w / 2, I.y + I.h, R.x + R.w / 2, R.y), 'wan', [I.x + I.w / 2 + 6, (I.y + I.h + R.y) / 2 + 4], 'start');
    else this.nodes.wanEdge = this.edge(curveH(I.x + I.w, I.y + I.h / 2, R.x, R.y + R.h / 2 + 8), 'wan', [(I.x + I.w + R.x) / 2, I.y + I.h / 2 - 2]);
    this.nodes.inet = this.box(nl, I, t('internet'), '', 'inet');
    this.hover(this.nodes.inet.g, () => this.tipWan(S));
    // 路由器 → 交换机 → AP
    if (M) {
      this.nodes.lanEdge = this.edge(curveV(R.x + 34, R.y + R.h, W.x + 34, W.y), 'lan', [R.x + 40, (R.y + R.h + W.y) / 2 + 4], 'start');
      this.nodes.apEdge = cfg.wifiVia === 'router'
        ? this.edge(curveV(R.x + R.w - 30, R.y + R.h, A.x + A.w - 30, A.y), 'wifi', [A.x + A.w - 36, (W.y + W.h + A.y) / 2 + 4], 'end')
        : this.edge(curveV(W.x + 34, W.y + W.h, A.x + 34, A.y), 'lan', [W.x + 40, (W.y + W.h + A.y) / 2 + 4], 'start');
    } else {
      this.nodes.lanEdge = this.edge(curveH(R.x + R.w, R.y + 18, W.x, W.y + W.h / 2), 'lan', [(R.x + R.w + W.x) / 2 + 26, (R.y + W.y + W.h / 2) / 2 + 2]);
      this.nodes.apEdge = cfg.wifiVia === 'router'
        ? this.edge(curveH(R.x + R.w, R.y + R.h - 18, A.x, A.y + A.h / 2), 'wifi', [(R.x + R.w + A.x) / 2 + 26, (R.y + R.h + A.y + A.h / 2) / 2])
        : this.edge(curveV(W.x + W.w / 2, W.y + W.h, A.x + A.w / 2, A.y), 'lan', [W.x + W.w / 2 + 8, (W.y + W.h + A.y) / 2 + 4], 'start');
    }
    // 交换机 → 有线设备，AP → 无线设备
    const addDev = (mac, i, g, from, type) => {
      const d = devMap[mac]; if (!d) return;
      const y = g.y + i * GAP, [fx, fy] = rightMid(from);
      const e = this.edge(curveH(fx, fy, g.x, y + PH / 2), type);
      const p = this.pill(nl, g.x, y, g.w, d.name, type);
      this.nodes.dev[mac] = { p, e };
      this.hover(p.g, () => this.tipDev(S, mac));
    };
    this.order.wired.forEach((m, i) => addDev(m, i, P.wired, W, 'lan'));
    this.order.wifi.forEach((m, i) => addDev(m, i, P.wifi, A, 'wifi'));

    this.nodes.router = this.box(nl, R, s.router.hostname || 'OpenWrt', '', 'router');
    this.hover(this.nodes.router.g, () => this.tipRouter(S));
    this.nodes.sw = this.box(nl, W, cfg.lanName || t('lanNode'), s.router.lan_cidr || '', 'sw');
    this.nodes.ap = this.box(nl, A, cfg.wifiName || t('wifiNode'), '', 'ap');
    // 左下角：WAN 90 秒实时曲线（仅桌面）
    if (P.chart) {
      const c = P.chart, g = el('g', { class: 'mini' }, nl);
      el('text', { x: c.x, y: c.y - 8, class: 'grp-title' }, g, t('wanChart'));
      el('rect', { x: c.x, y: c.y, width: c.w, height: c.h, rx: 7, class: 'mini-bg' }, g);
      for (let k = 1; k < 4; k++) el('line', { x1: c.x, x2: c.x + c.w, y1: c.y + c.h * k / 4, y2: c.y + c.h * k / 4, class: 'mini-grid' }, g);
      this.nodes.chart = { c, rxA: el('path', { class: 'mini-rx-a' }, g), rx: el('path', { class: 'mini-rx' }, g), tx: el('path', { class: 'mini-tx' }, g),
        max: el('text', { x: c.x + c.w - 6, y: c.y + 13, class: 'mini-lbl mono', 'text-anchor': 'end' }, g, ''),
        leg: el('text', { x: c.x + 8, y: c.y + 14, class: 'mini-lbl mono' }, g, '') };
    }
  };

  Flow.prototype.drawChart = function (S) {
    const o = this.nodes.chart; if (!o) return;
    const c = o.c, a = S.hist.wanRx, b = S.hist.wanTx; if (a.length < 2) return;
    const max = Math.max(1, ...a, ...b) * 1.15, N = 90;
    const pts = arr => arr.map((v, i) => [(c.x + (i + N - arr.length) / (N - 1) * c.w).toFixed(1), (c.y + c.h - v / max * (c.h - 22)).toFixed(1)]);
    const pa = pts(a), pb = pts(b);
    o.rx.setAttribute('d', 'M' + pa.map(p => p.join(',')).join(' L'));
    o.rxA.setAttribute('d', `M${pa[0][0]},${c.y + c.h} L` + pa.map(p => p.join(',')).join(' L') + ` L${pa[pa.length - 1][0]},${c.y + c.h} Z`);
    o.tx.setAttribute('d', 'M' + pb.map(p => p.join(',')).join(' L'));
    o.max.textContent = fmt(max) + ' Mbps';
    o.leg.textContent = `↓ ${fmt(a[a.length - 1])}   ↑ ${fmt(b[b.length - 1])}`;
  };

  Flow.prototype.render = function (S) {
    const s = S.cur; if (!s) return;
    this.pickOrder(S, s);
    this.mobile = this.svg.parentNode.clientWidth < 700;
    const key = [this.mobile ? 'm' : 'd', I18N.lang, this.order.wired.join(), this.order.wifi.join(), this.order.wg.join(), s.router.hostname].join('|');
    if (key !== this.key) { this.build(S, s); this.key = key; }
    const r = S.rates, n = this.nodes, t = I18N.t, now = s.ts / 1000;
    const setE = (e, v, txt) => { if (!e) return; e.rate = v; e.p.setAttribute('stroke-width', (1.3 + Math.min(3.6, Math.log10(1 + v) * 1.45)).toFixed(2)); e.p.classList.toggle('idle', v < 0.01); if (e.label && txt != null) e.label.textContent = txt; };
    setE(n.wanEdge, r.wan.rx + r.wan.tx, `↓${fmt(r.wan.rx)}  ↑${fmt(r.wan.tx)}`);
    n.inet.sub.textContent = s.wan.ipv4 ? (s.wan.proto || '').toUpperCase() + ' · ' + s.wan.ipv4 : 'IPv4 —';
    n.router.sub.textContent = (s.router.lan_ip || '') + (this.mobile ? '' : ' · NAT / FW / WG');
    let lanSum = 0, wifiSum = 0, wifiN = 0;
    s.devices.forEach(d => { const v = r.dev[d.mac] || { rx: 0, tx: 0 }; if (d.link === 'wifi') { wifiSum += v.rx + v.tx; wifiN++; } else lanSum += v.rx + v.tx; });
    setE(n.lanEdge, lanSum + wifiSum, fmt(lanSum + wifiSum) + ' Mbps');
    setE(n.apEdge, wifiSum, fmt(wifiSum) + ' Mbps');
    n.ap.sub.textContent = this.mobile ? `${wifiN} ${t('clients')}` : `2.4G + 5G · ${wifiN} ${t('clients')}`;
    for (const mac in n.dev) {
      const v = r.dev[mac] || { rx: 0, tx: 0 }, tot = v.rx + v.tx, o = n.dev[mac];
      o.p.val.textContent = fmt(tot); setE(o.e, tot);
      o.p.g.classList.toggle('hot', tot >= this.cfg.burstMbps);
    }
    this.drawChart(S);
    s.wg.forEach(w => {
      const o = n.wg[w.pubkey]; if (!o) return;
      const v = r.wg[w.pubkey] || { rx: 0, tx: 0 }, tot = v.rx + v.tx, ok = w.handshake > 0 && now - w.handshake < 180;
      o.p.val.textContent = ok ? fmt(tot) : '—'; setE(o.e, ok ? tot : 0);
      o.p.g.classList.toggle('down', !ok);
    });
  };

  Flow.prototype.animate = function (ts) {
    const dt = this.lastT ? Math.min(0.1, (ts - this.lastT) / 1000) : 0; this.lastT = ts;
    if (!document.hidden && !this.paused) this.edges.forEach(e => {
      if (e.rate > 0.01) { e.off -= dt * Math.min(70, 8 + Math.log10(1 + e.rate) * 24); e.p.setAttribute('stroke-dashoffset', e.off.toFixed(1)); }
    });
    requestAnimationFrame(this.animate.bind(this));
  };

  // ---- 悬停提示 ----
  const B = window.PulseFmt = {
    bytes(b) { const u = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']; let i = 0; while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; } return (i ? b.toFixed(b >= 100 ? 0 : 1) : b) + ' ' + u[i]; },
    mbps: fmt,
    ago(sec) { const t = I18N.t; if (!(sec >= 0) || sec > 1e9) return t('never'); if (sec < 60) return Math.round(sec) + t('sec') + t('ago'); if (sec < 3600) return Math.round(sec / 60) + t('min') + t('ago'); if (sec < 86400) return Math.round(sec / 3600) + t('hour') + t('ago'); return Math.round(sec / 86400) + t('day') + t('ago'); },
    esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
  };
  Flow.prototype.tipDev = function (S, mac) {
    const d = S.cur.devices.find(x => x.mac === mac); if (!d) return '';
    const v = S.rates.dev[mac] || { rx: 0, tx: 0 }, t = I18N.t, c = S.lastConns[mac];
    return `<b>${B.esc(d.name)}</b><br>${d.ip} · ${d.mac}<br>${d.link === 'wifi' ? t('wireless') + ' ' + (d.band || '') + (d.signal ? ' · ' + d.signal + ' dBm' : '') : t('wired')}<br>↓ ${fmt(v.rx)} Mbps · ↑ ${fmt(v.tx)} Mbps${c != null ? '<br>' + t('thConn') + ' ' + c : ''}<br>${t('thTotal')} ${B.bytes(d.rx_bytes)} / ${B.bytes(d.tx_bytes)}`;
  };
  Flow.prototype.tipWg = function (S, k) {
    const w = S.cur.wg.find(x => x.pubkey === k); if (!w) return '';
    const v = S.rates.wg[k] || { rx: 0, tx: 0 }, t = I18N.t;
    return `<b>${B.esc(w.name || w.pubkey)}</b><br>${B.esc(w.iface)} · ${B.esc(w.pubkey)}<br>${t('thEndpoint')} ${B.esc(w.endpoint)}<br>${t('thAllowed')} ${B.esc(w.allowed)}<br>${t('thHs')} ${B.ago(S.cur.ts / 1000 - w.handshake)}<br>↓ ${fmt(v.rx)} · ↑ ${fmt(v.tx)} Mbps`;
  };
  Flow.prototype.tipWan = function (S) {
    const s = S.cur, r = S.rates.wan;
    return `<b>WAN · ${B.esc(s.wan.device)}</b><br>IPv4 ${B.esc(s.wan.ipv4 || '—')}<br>IPv6 ${B.esc(s.wan.ipv6 || '—')}<br>↓ ${fmt(r.rx)} Mbps · ↑ ${fmt(r.tx)} Mbps`;
  };
  Flow.prototype.tipRouter = function (S) {
    const r = S.cur.router, t = I18N.t;
    return `<b>${B.esc(r.hostname)}</b><br>${B.esc(r.model)}<br>${B.esc(r.release)}<br>${t('load')} ${r.load.map(x => x.toFixed(2)).join(' ')}<br>${t('mem')} ${B.bytes(r.mem_total - r.mem_avail)} / ${B.bytes(r.mem_total)}`;
  };

  window.PulseFlow = Flow;
})();
