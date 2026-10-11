/* openwrt-pulse 前端配置。按需修改，或用 URL 参数覆盖：
 *   ?mock=1                         强制模拟数据
 *   ?endpoint=http://192.168.1.1/cgi-bin/pulse   指定采集器地址（PC 上打开时用）
 *   ?token=xxxx                     采集器口令（与路由器 /etc/config/pulse 中一致）
 *   ?lang=en  ?theme=dark
 */
window.PULSE_CONFIG = {
  endpoint: '/cgi-bin/pulse',   // 部署在路由器 /www/pulse/ 时，同源访问
  token: '',
  intervalMs: 1000,             // 刷新间隔
  fullEvery: 5,                 // 每 N 次请求一次带连接数明细的完整数据（降低路由器负载）
  lanName: '',                  // 留空 = 按界面语言显示「内网 / 交换机」
  wifiName: '',                 // 留空 = 「无线 AP」
  wifiVia: 'switch',            // 'switch' = AP 挂在交换机下（瘦 AP / 有线回程）；'router' = 路由器自带射频
  maxWired: 7, maxWireless: 8, maxWg: 6,
  burstMbps: 20,                // 单设备超过此速率且为均值 3 倍以上 → 记为突发
  wanBurstMbps: 50,
  connSpikePct: 30,             // 连接数 1 秒内上涨超过 30% → 连接激增
  aliases: {                    // MAC → 自定义名称（优先于 DHCP 主机名）
    // 'aa:bb:cc:dd:ee:ff': '书房台式机'
  }
};
