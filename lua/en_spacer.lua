-- 英文词条上屏自动空格 + 句首大写 + 单独的 i → I
-- 仅在英文模式下由 schema 的 filter 调用（须排在最后一两位）。
-- 空格统一加在「下一个词的前面」，所以标点前面永远不会多出空格：hello, world.
-- 规则：
-- 1. 光标前是英文单词 / 逗号等 / 句号等 → 新英文词前补一个空格；
-- 2. 一段话的开头、句号、问号、感叹号、换行之后 → 新词首字母大写（en_spacer/auto_capitalize: false 可关闭）；
-- 3. 单独的 i、i'm、i'll… 写成大写 I；
-- 4. 光标前是空格、中文、引号括号、或位置不明（刚删除 / 移动过光标）时不补空格。
local S = require("en_state")

local F = {}

function F.init(env)
  local cfg = env.engine.schema.config
  local v = cfg:get_bool("en_spacer/auto_capitalize")
  env.auto_cap = (v == nil) and true or v
  local v2 = cfg:get_bool("en_spacer/capital_i")
  env.capital_i = (v2 == nil) and true or v2
  env.idle = cfg:get_int("en_spacer/idle_reset_seconds") or 60
  local v3 = cfg:get_bool("en_spacer/mixed_mode_space")
  env.mixed_space = (v3 == nil) and true or v3
end

-- 只处理「纯英文词 / 几个词」：字母、撇号、连字符、词间空格
local function is_wordy(text)
  return text:match("^[%a][%a' %-]*$") ~= nil
end

local function fix_i(text)
  -- 独立的 i（后面是空格、撇号或结尾）→ I
  text = text:gsub("^i(['%s])", "I%1"):gsub("^i$", "I")
  text = text:gsub("(%s)i(['%s])", "%1I%2"):gsub("(%s)i$", "%1I")
  return text
end

function F.func(input, env)
  local ctx = env.engine.context
  -- 中英混输：只做「英文词前补空格」，不做句首大写和 I 大写
  if not ctx:get_option("en_mode") then
    S.check_idle(env.idle)
    if not env.mixed_space or not S.needs_space() then
      for cand in input:iter() do yield(cand) end
      return
    end
    for cand in input:iter() do
      local c = cand
      if is_wordy(c.text) then
        c = c:to_shadow_candidate("en_spacer", " " .. c.text, c.comment)
      end
      yield(c)
    end
    return
  end

  S.check_idle(env.idle)
  local space = S.needs_space()
  local cap = env.auto_cap and S.needs_cap()

  for cand in input:iter() do
    local c = cand
    local text = c.text
    if is_wordy(text) then
      local new = text
      if env.capital_i then new = fix_i(new) end
      if cap and new:match("^%l") then new = new:sub(1, 1):upper() .. new:sub(2) end
      if space then new = " " .. new end
      if new ~= text then
        c = c:to_shadow_candidate("en_spacer", new, c.comment)
      end
    end
    yield(c)
  end
end

return { init = F.init, func = F.func }
