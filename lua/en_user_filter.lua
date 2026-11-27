-- 英文模式·个人词库与拼写纠正（放在 en_mode_filter 后面、en_spacer 前面）：
--   · 常见拼写错误（teh、recieve…）→ 第一位给出正确写法；
--   · 你常打的词（人名、品牌、专业词）→ 打到前几个字母就出现在前面。
-- 配置：en_user: { enabled: true, max_candidates: 3 }
local U = require("en_user")

local F = {}

function F.init(env)
  local cfg = env.engine.schema.config
  local v = cfg:get_bool("en_user/enabled")
  env.enabled = (v == nil) and true or v
  env.max = cfg:get_int("en_user/max_candidates") or 3
end

function F.func(input, env)
  local ctx = env.engine.context
  local code = ctx.input
  if not env.enabled or not ctx:get_option("en_mode") or not code:match("^[%a']+$") or #code < 2 then
    for cand in input:iter() do yield(cand) end
    return
  end

  local low = code:lower()
  local seg = ctx.composition:back()
  local s, e = seg and seg.start or 0, seg and seg._end or #code
  local function make(text, comment)
    return Candidate("en_user", s, e, text, comment or "")
  end

  local fix = U.typo(low)
  if fix then yield(make(fix, " 纠正")) end
  local mine = U.match(low, env.max)

  local i, emitted = 0, false
  local function emit_mine()
    if emitted then return end
    emitted = true
    for _, w in ipairs(mine) do yield(make(w, "")) end
  end
  for cand in input:iter() do
    i = i + 1
    if i == 1 and cand.text:lower() ~= low then emit_mine() end
    yield(cand)
    if i == 1 then emit_mine() end
  end
  emit_mine()
end

return { init = F.init, func = F.func }
