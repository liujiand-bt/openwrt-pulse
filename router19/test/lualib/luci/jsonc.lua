-- 假 luci.jsonc：借 python 解析后转成 Lua 表（仅测试用）
local M = {}
function M.parse(s)
  local f = io.open("/tmp/pulse-jc.json", "w"); f:write(s); f:close()
  local p = io.popen([[python3 -c "
import json
def L(v):
    if isinstance(v,dict): return '{'+','.join('[%s]=%s'%(json.dumps(k),L(x)) for k,x in v.items())+'}'
    if isinstance(v,list): return '{'+','.join(L(x) for x in v)+'}'
    if isinstance(v,bool): return 'true' if v else 'false'
    if v is None: return 'nil'
    return json.dumps(v,ensure_ascii=False)
print('return '+L(json.load(open('/tmp/pulse-jc.json'))))"]])
  local code = p:read("*a"); p:close(); return loadstring(code)()
end
return M
