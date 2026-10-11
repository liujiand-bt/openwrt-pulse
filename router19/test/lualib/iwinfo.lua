-- 假 libiwinfo-lua（2018 API：iwinfo.type(dev) -> "wext"/"nl80211"/"qcawifi"）
local data = { ath1 = { ssid = "JDC-5G", freq = 5745, chan = 149, list = { ["A8:5C:2C:61:7F:12"] = { signal = -55 }, ["F2:1A:9C:44:01:11"] = { signal = -48 } } },
               ath0 = { ssid = "JDC-2.4G", freq = 2437, chan = 6, list = { ["00:00:00:50:3D:B5"] = { signal = -62 }, ["50:EC:50:1D:28:14"] = { signal = -57 } } } }
local api = { ssid = function(d) return data[d].ssid end, frequency = function(d) return data[d].freq end, channel = function(d) return data[d].chan end,
  mode = function() return "Master" end, assoclist = function(d) return data[d].list end }
return { type = function(d) return data[d] and "wext" or nil end, wext = api }
