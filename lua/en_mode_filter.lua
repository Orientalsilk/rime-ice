-- 英文模式·过滤：英文模式（开关 en_mode）开着、且输入全是字母时，
-- 候选里只留英文，汉字、emoji 等全部隐藏。
-- 用法：filters 里加（放第一位）  - lua_filter@*en_mode_filter

local OPTION = "en_mode"

local F = {}

-- 英文候选：全是可见的英文键盘字符（字母、数字、空格、标点符号）。
-- 这样自定义短语里的邮箱（a@b.com）、TODO、k8s 这类也会保留，汉字、emoji 才被隐藏
local function is_english(text)
  return text:match("^[\32-\126]+$") ~= nil
end

function F.func(input, env)
  local ctx = env.engine.context
  -- 只有「英文模式开 + 当前输入全是字母/撇号」才过滤，其他输入（数字、符号等）原样放行
  if not ctx:get_option(OPTION) or not ctx.input:match("^[%a']+$") then
    for cand in input:iter() do yield(cand) end
    return
  end
  for cand in input:iter() do
    if is_english(cand.text) then yield(cand) end
  end
end

return { func = F.func }
