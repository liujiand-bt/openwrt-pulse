-- 假 libuci-lua
local D = { pulse = { main = { [".type"] = "pulse", token = os.getenv("PULSE_TEST_TOKEN") or "", counters = "auto", cors_origin = "*" } },
  dhcp = { h1 = { [".type"] = "host", name = "NAS-DS920", mac = "00:11:32:AA:5E:02" } },
  network = { p1 = { [".type"] = "wireguard_wg0", public_key = "PEERKEY1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=", description = "我的手机", allowed_ips = { "10.8.0.2/32" } } } }
return { cursor = function() return {
  get = function(self, c, s, o) return D[c] and D[c][s] and D[c][s][o] end,
  foreach = function(self, c, t, fn) for _, s in pairs(D[c] or {}) do if t == nil or s[".type"] == t then fn(s) end end end } end }
