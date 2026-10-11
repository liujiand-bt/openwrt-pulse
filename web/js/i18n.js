(function () {
  'use strict';
  const D = {
    zh: {
      connect: '连接路由器', connTitle: '连接路由器', connEp: '采集器地址', connTok: '口令（/etc/config/pulse 里的 token）', connHint: '地址和口令只保存在本机浏览器里。路由器上需要设置 cors_origin（默认 *）。', useMock: '用模拟数据', cancel: '取消', err403: '口令错误 (403)',
      pause: '暂停', resume: '继续', live: '实时 · 1s', mock: '模拟数据 · 1s', paused: '已暂停', offline: '采集器离线',
      flowTitle: '流量流向图', flowSub: '线越粗越快 · 虚线流动速度 = 当前速率 · 悬停看详情',
      feedTitle: '实时事件', feedSub: '新设备 · 突发 · 连接 · 租约', devTitle: '内网 Top 设备', wgTitle: 'WireGuard 对端', ifTitle: '接口',
      cWanRx: 'WAN 下行', cWanTx: 'WAN 上行', cOnline: '在线设备', cWg: 'WireGuard', cConn: '活动连接', cDhcp: 'DHCP 租约', cRouter: '路由器',
      peak: '峰值', devices: '设备', wired: '有线', wireless: '无线', peersOnline: '在线', tunnels: '隧道', ofMax: '上限', leases: '租约', newest: '最新',
      load: '负载', mem: '内存', up: '运行',
      lgWan: 'WAN / 公网', lgWg: 'WireGuard', lgLan: '有线 LAN', lgWifi: '无线',
      internet: 'Internet', wanChart: 'WAN 最近 90 秒', lanNode: '内网 / 交换机', wifiNode: '无线 AP', wgPeers: 'WireGuard 对端', wiredTop: '有线设备 Top', wifiTop: '无线客户端 Top', clients: '客户端',
      fAll: '全部', fJoin: '设备', fBurst: '突发', fConn: '连接', fDhcp: '租约', fWg: '隧道',
      thName: '设备', thIp: 'IP', thMac: 'MAC', thLink: '接入', thDown: '下行', thUp: '上行', thConn: '连接', thTrend: '90s 趋势', thTotal: '累计 ↓/↑',
      thPeer: '对端', thEndpoint: '端点', thHs: '最近握手', thAllowed: '允许 IP', thIf: '接口', thDev: '设备', thState: '状态', thAddr: '地址', thRx: '接收', thTx: '发送',
      stUp: '启用', stDown: '停用', never: '从未', ago: '前', sec: '秒', min: '分', hour: '小时', day: '天',
      devSub: '{n} 台在线 · 计数来源 {src} · 按当前速率排序', wgSub: '{on}/{n} 在线 · 握手 180 秒内视为在线', ifSub: '{n} 个接口',
      evJoin: '新设备加入 {name}（{ip} · {link}）', evLeave: '设备离线 {name}（{ip}）', evLease: 'DHCP 分配 {ip} → {name}',
      evBurstDown: '{name} 下行突发 {v} Mbps（均值 {avg}）', evBurstUp: '{name} 上行突发 {v} Mbps（均值 {avg}）',
      evWanBurst: 'WAN 下行突发 {v} Mbps（均值 {avg}）', evConnSpike: '活动连接激增 {a} → {b}', evDevConn: '{name} 连接数 {a} → {b}',
      evWgDown: 'WireGuard {name} 握手超时', evWgUp: 'WireGuard {name} 重新连上（{ep}）',
      bannerMock: '无法连接采集器 {ep}，已切换为模拟数据。部署方法见 README。',
      footer: '数据源 {src} · 采集耗时 {ms} ms · 仅限内网访问，切勿暴露到公网'
    },
    en: {
      connect: 'Connect', connTitle: 'Connect to router', connEp: 'Collector URL', connTok: 'Token (from /etc/config/pulse)', connHint: 'Saved only in this browser. The router must allow CORS (cors_origin, default *).', useMock: 'Use mock data', cancel: 'Cancel', err403: 'Wrong token (403)',
      pause: 'Pause', resume: 'Resume', live: 'Live · 1s', mock: 'Mock data · 1s', paused: 'Paused', offline: 'Collector offline',
      flowTitle: 'Traffic flow', flowSub: 'thicker = faster · dash speed = current rate · hover for details',
      feedTitle: 'Live events', feedSub: 'joins · bursts · connections · leases', devTitle: 'Top LAN devices', wgTitle: 'WireGuard peers', ifTitle: 'Interfaces',
      cWanRx: 'WAN down', cWanTx: 'WAN up', cOnline: 'Online devices', cWg: 'WireGuard', cConn: 'Connections', cDhcp: 'DHCP leases', cRouter: 'Router',
      peak: 'peak', devices: 'devices', wired: 'wired', wireless: 'wireless', peersOnline: 'online', tunnels: 'tunnels', ofMax: 'max', leases: 'leases', newest: 'newest',
      load: 'load', mem: 'mem', up: 'up',
      lgWan: 'WAN / Internet', lgWg: 'WireGuard', lgLan: 'Wired LAN', lgWifi: 'Wireless',
      internet: 'Internet', wanChart: 'WAN · last 90 s', lanNode: 'LAN / switch', wifiNode: 'Wireless AP', wgPeers: 'WireGuard peers', wiredTop: 'Top wired', wifiTop: 'Top wireless', clients: 'clients',
      fAll: 'All', fJoin: 'Devices', fBurst: 'Bursts', fConn: 'Conns', fDhcp: 'DHCP', fWg: 'Tunnels',
      thName: 'Device', thIp: 'IP', thMac: 'MAC', thLink: 'Link', thDown: 'Down', thUp: 'Up', thConn: 'Conns', thTrend: '90s trend', thTotal: 'Total ↓/↑',
      thPeer: 'Peer', thEndpoint: 'Endpoint', thHs: 'Handshake', thAllowed: 'Allowed IPs', thIf: 'Interface', thDev: 'Device', thState: 'State', thAddr: 'Address', thRx: 'RX', thTx: 'TX',
      stUp: 'up', stDown: 'down', never: 'never', ago: ' ago', sec: 's', min: 'm', hour: 'h', day: 'd',
      devSub: '{n} online · counters: {src} · sorted by current rate', wgSub: '{on}/{n} online · handshake < 180 s', ifSub: '{n} interfaces',
      evJoin: 'New device {name} ({ip} · {link})', evLeave: 'Device left {name} ({ip})', evLease: 'DHCP lease {ip} → {name}',
      evBurstDown: '{name} download burst {v} Mbps (avg {avg})', evBurstUp: '{name} upload burst {v} Mbps (avg {avg})',
      evWanBurst: 'WAN download burst {v} Mbps (avg {avg})', evConnSpike: 'Connection spike {a} → {b}', evDevConn: '{name} connections {a} → {b}',
      evWgDown: 'WireGuard {name} handshake timed out', evWgUp: 'WireGuard {name} reconnected ({ep})',
      bannerMock: 'Cannot reach collector {ep}; showing mock data. See README to deploy.',
      footer: 'source {src} · collect {ms} ms · LAN only, never expose to the Internet'
    }
  };
  let lang = 'zh';
  window.I18N = {
    get lang() { return lang; },
    set(l) { lang = D[l] ? l : 'zh'; document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
      document.querySelectorAll('[data-i18n]').forEach(e => { e.textContent = this.t(e.dataset.i18n); }); },
    t(k, p) { let s = (D[lang][k] != null ? D[lang][k] : (D.zh[k] != null ? D.zh[k] : k));
      if (p) s = s.replace(/\{(\w+)\}/g, (m, n) => p[n] != null ? p[n] : m); return s; }
  };
})();
