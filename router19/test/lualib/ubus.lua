-- 假 libubus-lua：转调命令行替身，只为测试“有 Lua 绑定”时的代码路径
local M = {}
function M.connect() return { call = function(self, o, m, a)
  local p = io.popen("ubus call " .. o .. " " .. m .. " '{}'"); local s = p:read("*a"); p:close()
  if s == "" then return nil end
  local jc = require("luci.jsonc"); return jc.parse(s) end } end
return M
