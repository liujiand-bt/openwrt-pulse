/* openwrt-pulse 主程序：取数 → PulseState 计算 → 渲染卡片 / 流向图 / 事件 / 表格 */
(function () {
  'use strict';
  const Q = new URLSearchParams(location.search);
  const cfg = Object.assign({}, window.PULSE_CONFIG || {});
  // 优先级：URL 参数 > 本机保存的连接设置 > config.js
  const saved = (() => { try { return JSON.parse(localStorage.getItem('pulse.conn') || 'null'); } catch (e) { return null; } })();
  if (saved && saved.endpoint) { cfg.endpoint = saved.endpoint; cfg.token = saved.token || ''; }
  if (Q.get('endpoint')) cfg.endpoint = Q.get('endpoint');
  if (Q.get('token')) cfg.token = Q.get('token');
  const explicitEp = !!(Q.get('endpoint') || (saved && saved.endpoint));
  const $ = id => document.getElementById(id);
  const F = window.PulseFmt, fmt = F.mbps, esc = F.esc;
  const t = (k, p) => I18N.t(k, p);

  const tipEl = $('tip');
  const tip = {
    show(ev, html) { if (!html) return; tipEl.innerHTML = html; tipEl.style.display = 'block'; const x = ev.clientX + 14, y = ev.clientY + 14; tipEl.style.left = Math.min(x, innerWidth - tipEl.offsetWidth - 10) + 'px'; tipEl.style.top = Math.min(y, innerHeight - tipEl.offsetHeight - 10) + 'px'; },
    hide() { tipEl.style.display = 'none'; }
  };

  let S = new PulseState(cfg);
  const flow = new PulseFlow($('flow'), cfg, tip);
  // 直接双击打开 index.html（file://）且没设置过地址时，先用模拟数据，并弹出连接框
  let mode = (Q.get('mock') === '1' || (location.protocol === 'file:' && !explicitEp)) ? 'mock' : 'live';
  let mock = null, paused = false, tick = 0, lastCollectMs = 0, feedFilter = 'all', failCount = 0;

  // ---------- 主题 / 语言 ----------
  const theme = Q.get('theme') || localStorage.getItem('pulse.theme') || 'light';
  document.documentElement.dataset.theme = theme;
  I18N.set(Q.get('lang') || localStorage.getItem('pulse.lang') || 'zh');
  $('btnTheme').onclick = () => { const th = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; document.documentElement.dataset.theme = th; localStorage.setItem('pulse.theme', th); };
  $('btnLang').onclick = () => { I18N.set(I18N.lang === 'zh' ? 'en' : 'zh'); localStorage.setItem('pulse.lang', I18N.lang); staticTexts(); renderAll(true); };
  $('btnPause').onclick = () => { paused = !paused; flow.paused = paused; $('btnPause').textContent = t(paused ? 'resume' : 'pause'); badge(); };
  function staticTexts() {
    $('btnLang').textContent = I18N.lang === 'zh' ? 'EN' : '中';
    $('btnPause').textContent = t(paused ? 'resume' : 'pause');
    $('legend').innerHTML = [['wan', 'lgWan'], ['wg', 'lgWg'], ['lan', 'lgLan'], ['wifi', 'lgWifi']].map(([c, k]) => `<span class="lg"><i class="lg-${c}"></i>${t(k)}</span>`).join('');
    $('feedFilters').innerHTML = [['all', 'fAll'], ['join', 'fJoin'], ['burst', 'fBurst'], ['conn', 'fConn'], ['dhcp', 'fDhcp'], ['wg', 'fWg']].map(([f, k]) => `<button class="chip${f === feedFilter ? ' on' : ''}" data-f="${f}">${t(k)}</button>`).join('');
    document.querySelectorAll('#feedFilters .chip').forEach(b => b.onclick = () => { feedFilter = b.dataset.f; staticTexts(); renderFeed(true); });
    badge();
  }
  function badge() {
    const b = $('srcBadge');
    b.className = 'badge ' + (paused ? 'paused' : failCount > 2 ? 'bad' : mode === 'mock' ? 'mock' : 'live');
    $('srcText').textContent = paused ? t('paused') : failCount > 2 ? t('offline') : t(mode === 'mock' ? 'mock' : 'live');
  }

  // ---------- 取数 ----------
  async function fetchLive(full) {
    const u = new URL(cfg.endpoint, location.href);
    if (full) u.searchParams.set('full', '1');
    // 口令放在查询参数里：不带自定义请求头，跨域时就不会触发 OPTIONS 预检（老版本 uhttpd 不一定支持）
    if (cfg.token) u.searchParams.set('token', cfg.token);
    const t0 = performance.now();
    const res = await fetch(u, { cache: 'no-store' });
    if (!res.ok) throw new Error(res.status === 403 ? t('err403') : 'HTTP ' + res.status);
    const j = await res.json();
    lastCollectMs = j.collect_ms != null ? j.collect_ms : Math.round(performance.now() - t0);
    showWarnings(j.warnings);
    if (j.hints && j.hints.smooth && !Q.get('smooth') && cfg.smooth == null) S.smooth = j.hints.smooth;
    if (!j.ts) j.ts = Date.now();
    return j;
  }
  let warnKey = '';
  function showWarnings(w) {
    const k = (w || []).join('|'); if (k === warnKey) return; warnKey = k;
    const bn = $('banner'); bn.hidden = !k; bn.innerHTML = (w || []).map(x => '⚠ ' + esc(x)).join('<br>');
  }
  function openConn() {
    $('inEp').value = /^https?:/.test(cfg.endpoint || '') ? cfg.endpoint
      : /^https?:/.test(location.protocol) ? new URL(cfg.endpoint || '/cgi-bin/pulse', location.href).href : 'http://192.168.1.1/cgi-bin/pulse';
    $('inTok').value = cfg.token || '';
    $('connDlg').showModal();
  }
  $('btnConn').onclick = openConn;
  $('connDlg').addEventListener('close', () => {
    const v = $('connDlg').returnValue;
    if (v === 'ok') { localStorage.setItem('pulse.conn', JSON.stringify({ endpoint: $('inEp').value.trim(), token: $('inTok').value.trim() })); location.href = location.pathname; }
    if (v === 'mock') { localStorage.removeItem('pulse.conn'); location.href = location.pathname + '?mock=1'; }
  });
  function switchToMock(reason) {
    mode = 'mock'; failCount = 0;
    const bn = $('banner'); bn.hidden = false; bn.textContent = t('bannerMock', { ep: cfg.endpoint }) + (reason ? ' (' + reason + ')' : '');
    startMock(); badge();
  }
  function startMock() {
    mock = new PulseMock(); const sm = S.smooth; S = new PulseState(cfg); S.smooth = sm;
    // 预热：模拟过去 180 秒，让曲线、峰值、事件流一打开就有内容
    const now = Date.now(), N = 180;
    mock.init(now - (N + 1) * 1000);
    for (let i = N; i >= 1; i--) S.ingest(mock.step(now - i * 1000, 1, i % cfg.fullEvery === 0));
  }

  async function loop() {
    const started = performance.now();
    if (!paused) {
      tick++;
      const full = tick % cfg.fullEvery === 1 || tick === 1;
      try {
        if (mode === 'mock') { const t0 = performance.now(); S.ingest(mock.step(Date.now(), 1, full)); lastCollectMs = Math.round(performance.now() - t0); }
        else { S.ingest(await fetchLive(full)); failCount = 0; }
        renderAll();
      } catch (e) {
        failCount++; badge();
        if (!S.cur && failCount >= 2) switchToMock(e.message);
      }
    }
    $('clock').textContent = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    setTimeout(loop, Math.max(100, cfg.intervalMs - (performance.now() - started)));
  }

  // ---------- 渲染 ----------
  const spark = (arr, cls) => {
    if (!arr || arr.length < 2) return '<svg class="spark"></svg>';
    const max = Math.max(0.05, ...arr), n = arr.length;
    const pts = arr.map((v, i) => `${(i / (n - 1) * 100).toFixed(1)},${(21.5 - v / max * 18).toFixed(1)}`);
    return `<svg class="spark ${cls || ''}" viewBox="0 0 100 22" preserveAspectRatio="none"><path class="sa" d="M0,22 L${pts.join(' L')} L100,22 Z"/><path class="sl" d="M${pts.join(' L')}"/></svg>`;
  };
  const card = (label, val, unit, sub, extra, cls) => `<div class="card ${cls || ''}"><div class="c-label">${label}</div><div class="c-val mono">${val}<small>${unit || ''}</small></div><div class="c-sub mono">${sub}</div>${extra || ''}</div>`;

  function renderCards() {
    const s = S.cur, r = S.rates;
    const online = s.devices.filter(d => d.online !== false), wifiN = online.filter(d => d.link === 'wifi').length;
    const now = s.ts / 1000, wgOn = s.wg.filter(w => w.handshake > 0 && now - w.handshake < 180).length;
    const tunnels = new Set(s.wg.map(w => w.iface)).size;
    const ct = s.conntrack, pct = ct.max ? ct.count / ct.max * 100 : 0;
    const newest = s.leases.slice().sort((a, b) => b.expires - a.expires)[0];
    const memPct = s.router.mem_total ? (1 - s.router.mem_avail / s.router.mem_total) * 100 : 0;
    const up = s.router.uptime, upTxt = up > 86400 ? Math.floor(up / 86400) + t('day') : Math.floor(up / 3600) + t('hour');
    $('cards').innerHTML = [
      card(t('cWanRx'), fmt(r.wan.rx), ' Mbps', `${t('peak')} ${fmt(S.peak.rx)} Mbps`, spark(S.hist.wanRx, 'wan'), 'c-wan'),
      card(t('cWanTx'), fmt(r.wan.tx), ' Mbps', `${t('peak')} ${fmt(S.peak.tx)} Mbps`, spark(S.hist.wanTx, 'wanup'), 'c-wan'),
      card(t('cOnline'), online.length, ' ' + t('devices'), `${t('wired')} ${online.length - wifiN} · ${t('wireless')} ${wifiN}`),
      card(t('cWg'), `${wgOn}<span class="dim"> / ${s.wg.length}</span>`, ' peers', `${t('peersOnline')} ${wgOn} · ${tunnels} ${t('tunnels')}`),
      card(t('cConn'), ct.count.toLocaleString(), '', `${t('ofMax')} ${ct.max.toLocaleString()} · ${pct.toFixed(1)}%`, spark(S.hist.ct, 'ct')),
      card(t('cDhcp'), s.leases.length, ' ' + t('leases'), newest ? `${t('newest')} ${esc(newest.name || newest.ip)}` : '—'),
      card(t('cRouter'), s.router.load[0].toFixed(2), ' ' + t('load'), `${t('mem')} ${memPct.toFixed(0)}% · ${t('up')} ${upTxt}`)
    ].join('');
    $('hostLabel').textContent = `${s.router.hostname} · ${s.router.release || ''}`;
  }

  let feedKey = '';
  function renderFeed(force) {
    const list = S.events.filter(e => feedFilter === 'all' || e.type === feedFilter || (feedFilter === 'join' && e.type === 'leave') || (feedFilter === 'burst' && e.type === 'wan'));
    const key = feedFilter + I18N.lang + (list[0] ? list[0].ts + list.length : 0);
    if (!force && key === feedKey) return; feedKey = key;
    const p = e => { const o = Object.assign({}, e.params); ['v', 'avg'].forEach(k => { if (typeof o[k] === 'number') o[k] = fmt(o[k]); });
      if (o.link) o.link = o.link === 'wifi' ? t('wireless') + (o.band ? ' ' + o.band : '') : t('wired'); for (const k in o) o[k] = esc(o[k]); return o; };
    $('feed').innerHTML = list.slice(0, 120).map(e => `<li class="ev ev-${e.type}${Date.now() - e.ts < 2500 ? ' new' : ''}"><time>${new Date(e.ts).toLocaleTimeString('zh-CN', { hour12: false })}</time><i></i><span>${t(e.key, p(e))}</span></li>`).join('');
  }

  function renderTables() {
    const s = S.cur, r = S.rates;
    const devs = s.devices.slice().sort((a, b) => { const ra = r.dev[a.mac] || { rx: 0, tx: 0 }, rb = r.dev[b.mac] || { rx: 0, tx: 0 }; return (rb.rx + rb.tx) - (ra.rx + ra.tx) || (S.ema.dev[b.mac] || 0) - (S.ema.dev[a.mac] || 0); });
    $('devSub').textContent = t('devSub', { n: devs.length, src: s.counter_source || '—' });
    $('tblDevices').innerHTML = `<thead><tr><th>${t('thName')}</th><th>${t('thIp')}</th><th class="hide-m">${t('thMac')}</th><th>${t('thLink')}</th><th class="num">${t('thDown')}</th><th class="num">${t('thUp')}</th><th class="num hide-m">${t('thConn')}</th><th class="hide-m">${t('thTrend')}</th><th class="num hide-m">${t('thTotal')}</th></tr></thead><tbody>` +
      devs.slice(0, 12).map(d => { const v = r.dev[d.mac] || { rx: 0, tx: 0 }, c = S.lastConns[d.mac];
        return `<tr><td><i class="ld ld-${d.link === 'wifi' ? 'wifi' : 'lan'}"></i>${esc(d.name)}</td><td class="mono">${esc(d.ip)}</td><td class="mono dim hide-m">${esc(d.mac)}</td><td>${d.link === 'wifi' ? t('wireless') + ' ' + esc(d.band) + (d.signal ? ` <span class="dim mono">${d.signal}dBm</span>` : '') : t('wired')}</td><td class="num mono">${fmt(v.rx)}</td><td class="num mono">${fmt(v.tx)}</td><td class="num mono hide-m">${c != null ? c : '—'}</td><td class="hide-m">${spark(S.hist.dev[d.mac], d.link === 'wifi' ? 'wifi' : 'lan')}</td><td class="num mono dim hide-m">${F.bytes(d.rx_bytes)} / ${F.bytes(d.tx_bytes)}</td></tr>`; }).join('') + '</tbody>';
    const now = s.ts / 1000, on = s.wg.filter(w => now - w.handshake < 180).length;
    $('wgSub').textContent = t('wgSub', { on, n: s.wg.length });
    $('tblWg').innerHTML = `<thead><tr><th>${t('thPeer')}</th><th class="hide-m">${t('thEndpoint')}</th><th>${t('thHs')}</th><th class="num">↓ Mbps</th><th class="num">↑ Mbps</th><th class="num hide-m">${t('thTotal')}</th></tr></thead><tbody>` +
      s.wg.map(w => { const v = r.wg[w.pubkey] || { rx: 0, tx: 0 }, ok = w.handshake > 0 && now - w.handshake < 180;
        return `<tr class="${ok ? '' : 'off'}"><td><i class="sd ${ok ? 'ok' : ''}"></i>${esc(w.name || w.pubkey)}<div class="dim mono small">${esc(w.iface)} · ${esc(w.allowed)}</div></td><td class="mono dim hide-m">${esc(w.endpoint)}</td><td class="mono">${w.handshake ? F.ago(now - w.handshake) : t('never')}</td><td class="num mono">${fmt(v.tx)}</td><td class="num mono">${fmt(v.rx)}</td><td class="num mono dim hide-m">${F.bytes(w.tx_bytes)} / ${F.bytes(w.rx_bytes)}</td></tr>`; }).join('') + '</tbody>';
    $('ifSub').textContent = t('ifSub', { n: s.interfaces.length });
    $('tblIf').innerHTML = `<thead><tr><th>${t('thIf')}</th><th>${t('thState')}</th><th class="hide-m">${t('thAddr')}</th><th class="num">${t('thRx')} Mbps</th><th class="num">${t('thTx')} Mbps</th><th class="num hide-m">${t('thTotal')}</th></tr></thead><tbody>` +
      s.interfaces.map(i => { const v = r.ifc[i.device] || { rx: 0, tx: 0 };
        return `<tr class="${i.up ? '' : 'off'}"><td><i class="ld ld-${i.kind === 'wan' ? 'wan' : i.kind === 'wg' ? 'wg' : i.kind === 'wifi' ? 'wifi' : 'lan'}"></i>${esc(i.name)} <span class="dim mono small">${esc(i.device)}</span></td><td>${i.up ? `<span class="st ok">${t('stUp')}</span>` : `<span class="st">${t('stDown')}</span>`}${i.speed ? ` <span class="dim mono small">${esc(i.speed)}</span>` : ''}</td><td class="mono dim hide-m">${esc(i.ipv4 || '—')}</td><td class="num mono">${fmt(v.rx)}</td><td class="num mono">${fmt(v.tx)}</td><td class="num mono dim hide-m">${F.bytes(i.rx_bytes)} / ${F.bytes(i.tx_bytes)}</td></tr>`; }).join('') + '</tbody>';
    $('foot').textContent = t('footer', { src: mode === 'mock' ? 'mock' : cfg.endpoint, ms: lastCollectMs });
  }

  function renderAll(force) {
    if (!S.cur || !S.prev) return;
    renderCards(); flow.render(S); renderFeed(force); renderTables(); badge();
  }

  staticTexts();
  if (Q.get('smooth')) S.smooth = +Q.get('smooth'); else if (cfg.smooth != null) S.smooth = cfg.smooth;
  if (mode === 'mock') startMock();
  if (location.protocol === 'file:' && !explicitEp && Q.get('mock') !== '1') setTimeout(openConn, 300);
  loop();
})();
