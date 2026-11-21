-- 英文候选的音标 + 中文释义（取代 reverse_lookup_filter@en_comment 和 en_case_comment）。
-- 比自带的反查更省力：
--   · 汉字等非英文候选直接跳过，不查词库；
--   · 只给靠前的几个候选（max_candidates，默认 12）加释义，后面的不处理；
--   · 查过的词记在内存里，同一个词不重复查；
--   · 大写、首字母大写的写法（Hello、HELLO）自动转小写去查。
-- 开关在方案文件的 en_comment 里：enabled: false 就完全不加释义。
-- 用法：filters 里  - lua_filter@*en_comment_filter

local F = {}

function F.init(env)
  local config = env.engine.schema.config
  local en = config:get_bool("en_comment/enabled")
  env.enabled = (en == nil) and true or en
  env.budget = config:get_int("en_comment/max_candidates") or 12
  env.cache, env.cache_n = {}, 0
  env.db = nil
  if env.enabled then
    local ok, db = pcall(function() return ReverseDb("build/en_comment.reverse.bin") end)
    if ok then env.db = db end
  end
end

function F.func(input, env)
  local db = env.db
  if not db then
    for cand in input:iter() do yield(cand) end
    return
  end
  local cache, budget = env.cache, env.budget
  local n = 0
  for cand in input:iter() do
    n = n + 1
    if n <= budget then
      local text = cand.text
      local b = text:byte(1)
      if b and b < 128 and text:match("^%a[%a']*$") then
        local key = text:lower()
        local d = cache[key]
        if d == nil then
          local ok, res = pcall(function() return db:lookup(key) end)
          d = (ok and res and res ~= "") and (" " .. res:gsub("@+", " ")) or false
          if env.cache_n > 3000 then env.cache, env.cache_n = {}, 0; cache = env.cache end
          cache[key] = d
          env.cache_n = env.cache_n + 1
        end
        if d then cand:get_genuine().comment = d end
      end
    end
    yield(cand)
  end
end

return { init = F.init, func = F.func }
