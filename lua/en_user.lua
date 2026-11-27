-- 英文模式的个人词库：记住你常打的词（人名、品牌、专业词），再打时自动排前；
-- 并提供常见拼写错误的纠正表（en_typos.txt）。
-- 个人词库存在 Rime 用户目录的 en_user_words.txt（词<Tab>次数），可以直接用记事本编辑 / 删除不想要的词。
local U = { words = nil, typos = nil, dirty = 0, n = 0 }

local MAX_WORDS = 3000
local SAVE_EVERY = 40      -- 攒够这么多次记录，并且距上次写盘超过 SAVE_GAP 秒，才写一次文件
local SAVE_GAP = 120

local function user_dir()
  local ok, d = pcall(function() return rime_api.get_user_data_dir() end)
  return ok and d or "."
end

local function lua_dir()
  local src = debug.getinfo(1, "S").source or ""
  return src:match("^@(.+)[/\\][^/\\]+$") or (user_dir() .. "/lua")
end

function U.load()
  if U.words then return end
  U.words, U.n = {}, 0
  local f = io.open(user_dir() .. "/en_user_words.txt", "r")
  if f then
    for line in f:lines() do
      local w, c = line:match("^([^\t]+)\t(%d+)")
      if w then U.words[w] = tonumber(c); U.n = U.n + 1 end
    end
    f:close()
  end
end

function U.save()
  if not U.words or U.dirty == 0 then return end
  U.dirty = 0
  U.last_save = os.time()
  -- 太多时去掉次数最少的
  if U.n > MAX_WORDS then
    local arr = {}
    for w, c in pairs(U.words) do arr[#arr + 1] = { w, c } end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    U.words, U.n = {}, 0
    for i = 1, math.min(#arr, MAX_WORDS * 0.8 // 1) do U.words[arr[i][1]] = arr[i][2]; U.n = U.n + 1 end
  end
  -- 先写临时文件、写完再替换，万一中途断电 / 崩溃，原来的个人词库也不会被写坏
  local path = user_dir() .. "/en_user_words.txt"
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return end
  local ok = true
  for w, c in pairs(U.words) do
    if not f:write(w, "\t", c, "\n") then ok = false; break end
  end
  f:close()
  if ok then
    os.remove(path)
    if not os.rename(tmp, path) then
      -- 替换失败（极少见）：退回直接写，保证词库不丢
      local g = io.open(path, "w")
      if g then
        for w, c in pairs(U.words) do g:write(w, "\t", c, "\n") end
        g:close()
      end
      os.remove(tmp)
    end
  else
    os.remove(tmp)
  end
end

-- 记录刚上屏的文字里的英文词
function U.record(text)
  if not text or text == "" then return end
  U.load()
  for w in text:gmatch("[%a][%a'%-]*") do
    w = w:gsub("[%-']+$", "")
    if #w >= 2 and #w <= 30 and not w:find("^%u%u+$") then
      if U.words[w] == nil then U.n = U.n + 1 end
      U.words[w] = (U.words[w] or 0) + 1
      U.dirty = U.dirty + 1
    end
  end
  if U.dirty >= SAVE_EVERY and os.time() - (U.last_save or 0) >= SAVE_GAP then U.save() end
end

-- 以 low 开头、用过 2 次以上的个人词，次数多的在前，最多 max 个
function U.match(low, max)
  U.load()
  local arr = {}
  for w, c in pairs(U.words) do
    if c >= 2 and #w >= #low and w:lower():sub(1, #low) == low then arr[#arr + 1] = { w, c } end
  end
  table.sort(arr, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  local out = {}
  for i = 1, math.min(#arr, max) do out[i] = arr[i][1] end
  return out
end

function U.typo(low)
  if not U.typos then
    U.typos = {}
    local f = io.open(lua_dir() .. "/en_typos.txt", "r")
    if f then
      for line in f:lines() do
        local a, b = line:match("^([%a']+)\t(.+)$")
        if a then U.typos[a] = b end
      end
      f:close()
    end
  end
  return U.typos[low]
end

return U
