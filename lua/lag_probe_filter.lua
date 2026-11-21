-- 卡顿探针·候选端：第一个候选出来时，如果距按键已超过 80 毫秒，就在用户目录的 lag_probe.log 记一行
-- （时间 / 输入 / 耗时 / Lua 内存 / 是否英文模式 / 首选）。只记录，不改变任何候选；日志超过 200KB 自动清空。
-- 用法：filters 里 uniquifier 前面加  - lua_filter@*lag_probe_filter
local M = require("lag_probe_state")

local function func(input, env)
  local first = true
  for cand in input:iter() do
    if first then
      first = false
      if not M.fired and M.t0 then
        M.fired = true
        local dt = os.clock() - M.t0
        if dt >= M.threshold then
          local ctx = env.engine.context
          pcall(function()
            M.write(string.format("%s  慢 %.0f 毫秒  输入=%s  Lua内存=%.1fMB  英文模式=%s  首选=%s",
              os.date("%H:%M:%S"), dt * 1000, ctx.input, collectgarbage("count") / 1024,
              tostring(ctx:get_option("en_mode")), cand.text))
          end)
        end
      end
    end
    yield(cand)
  end
end

return func
