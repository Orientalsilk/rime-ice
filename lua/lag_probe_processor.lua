-- 卡顿探针·按键端：记下每次按键的开始时间，不处理按键。
-- 用法：processors 最前面加  - lua_processor@*lag_probe_processor
local M = require("lag_probe_state")

local function func(key, env)
  if not key:release() then
    M.t0 = os.clock()
    M.fired = false
  end
  return 2 -- kNoop：不处理，交给后面的
end

return func
