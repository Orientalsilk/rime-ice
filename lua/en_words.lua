-- 英文词表（给通配符、词性筛选、连写拆词用）。
-- 为了不拖慢输入法，整张词表只放在内存里的「一整段文字」里（对垃圾回收来说只是 1 个对象），
-- 不再拆成几十万个小对象；通配符 / 词性查询直接在这段文字里查，用到才读取。
-- 连写拆词只用最常用的前 20000 个词建一张小表。
local M = { data = nil, cost = {}, cost_ready = false }

local TOP_FOR_SPLIT = 20000

local function data_path()
  local src = debug.getinfo(1, "S").source or ""
  local dir = src:match("^@(.+)[/\\][^/\\]+$")
  if dir then return dir .. "/en_words.txt" end
  return "lua/en_words.txt"
end

-- 取整段词表文字（开头补一个换行，方便按「换行 + 词」定位）
function M.get()
  if M.data ~= nil then return M.data or nil end
  local f = io.open(data_path(), "r")
  if not f then
    local ok, dir = pcall(function() return rime_api.get_user_data_dir() end)
    if ok and dir then f = io.open(dir .. "/lua/en_words.txt", "r") end
  end
  if not f then
    M.data = false
    return nil
  end
  local s = f:read("a")
  f:close()
  M.data = "\n" .. s
  return M.data
end

-- 查询：lit 是词开头那段固定字母，pat 是整词的 Lua 匹配式（带括号捕获：词、释义）
-- 返回 { {词, 释义}, ... }，按常用程度排列，最多 max 个
function M.search(lit, pat, pos_pat, max)
  local data = M.get()
  local out = {}
  if not data then return out end
  local key = "\n" .. lit
  local pos = 1
  while #out < max do
    local s = data:find(key, pos, true)
    if not s then break end
    local w, c = data:match(pat, s + 1)
    if w and (not pos_pat or c:find(pos_pat)) then out[#out + 1] = { w, c } end
    pos = s + 1
  end
  return out
end

-- 词表里是否有这个词（整词）
function M.is_word(w)
  local data = M.get()
  return data ~= nil and data:find("\n" .. w .. "\t", 1, true) ~= nil
end

-- 连写拆词用的「常用词」：按真实使用频率排好，排得越前越优先。
-- 词表文件本身的顺序不是严格的词频，所以最常用的这几百个词在这里手工校正，
-- 否则 iamhappy 会拆不开、havean 之类会被拆成冷僻词（togo、iam）。
local CORE = [[
the be to of and a in that have i it for not on with he as you do at this but his by from they we say her she or an
will my one all would there their what so up out if about who get which go me when make can like time no just him
know take people into year your good some could them see other than then now look only come its over think also back
after use two how our work first well way even new want because any these give day most us is are was were am been
being has had did does done said made went got going ok okay yes yeah hello hi please thanks thank sorry love need
help tell call try ask feel leave put mean keep let begin seem show hear play run move live believe hold bring
happen write provide sit stand lose pay meet include continue set learn change lead understand watch follow stop
create speak read allow add spend grow open walk win offer remember consider appear buy wait serve die send expect
build stay fall cut reach kill remain much many more very too here where why still should must may might never
always again really right left little big small long great high old own same another each every both few
those such off down home house life world school place week night morning evening today tomorrow yesterday name
friend man woman child thing part problem fact word eat drink sleep sure maybe nice happy sad fine busy free
ready late early hard easy fast slow best better worse bad door water food money phone message text email
]]

-- 没有撇号的缩写写法 → 带撇号的正确写法（拆词时用）
local CONTR = {
  im = "i'm", ive = "i've", dont = "don't", cant = "can't", wont = "won't", isnt = "isn't",
  arent = "aren't", wasnt = "wasn't", werent = "weren't", didnt = "didn't", doesnt = "doesn't",
  couldnt = "couldn't", wouldnt = "wouldn't", shouldnt = "shouldn't", havent = "haven't",
  hasnt = "hasn't", hadnt = "hadn't", thats = "that's", whats = "what's", theres = "there's",
  heres = "here's", youre = "you're", theyre = "they're", youve = "you've", theyve = "they've",
  weve = "we've", youll = "you'll", theyll = "they'll", itll = "it'll", lets = "let's",
  hes = "he's", shes = "she's", whos = "who's",
}
-- 专有名词等词表里没有、但常打的词
local EXTRA = "china chinese english america american google iphone android wifi online app apps lua python github youtube wechat"

-- 两个字母以内、容易乱拆的词：只允许这些
local SHORT_OK = {}
for w in ("a i of to in is it he we me my be do go so no up us an as at by if on or am hi oh ok"):gmatch("%S+") do SHORT_OK[w] = true end

M.contr = CONTR

-- 连写拆词用的代价表（只含最常用的词）：第一次拆词时才建
function M.cost_table()
  if M.cost_ready then return M.cost end
  M.cost_ready = true
  local data = M.get()
  if not data then return M.cost end
  local cost = M.cost
  local logn = math.log(TOP_FOR_SPLIT)
  local i = 0
  for w in data:gmatch("\n([%l']+)\t[^\n]*") do
    i = i + 1
    if i > TOP_FOR_SPLIT then break end
    if not w:find("'", 1, true) then
      local c = math.log(i * logn)
      if i > 12000 then c = c + 1 end
      if #w <= 2 and not SHORT_OK[w] then c = c + 4 end
      if #w == 1 and w ~= "a" and w ~= "i" then c = c + 4 end
      cost[w] = c
    end
  end
  -- 常用词：覆盖为「按排位的低代价」
  local n = 0
  for w in CORE:gmatch("%S+") do
    n = n + 1
    local c = math.log(n * logn) - 0.5
    if not cost[w] or c < cost[w] then cost[w] = c end
  end
  for w in EXTRA:gmatch("%S+") do
    if not cost[w] then cost[w] = math.log(1500 * logn) end
  end
  for w in pairs(CONTR) do cost[w] = math.log(150 * logn) end
  return M.cost
end

-- 把 "ilovelua" 拆成 { "i", "love", "lua" }；拆不开返回 nil
function M.split(s)
  local n = #s
  if n == 0 or n > 60 then return nil end
  local cost = M.cost_table()
  local INF = 1e18
  local best, from = { [0] = 0 }, {}
  for i = 1, n do
    best[i] = INF
    for k = math.max(0, i - 20), i - 1 do
      local c = cost[s:sub(k + 1, i)]
      if c and best[k] + c < best[i] then
        best[i] = best[k] + c
        from[i] = k
      end
    end
  end
  if best[n] >= INF then return nil end
  local out, i = {}, n
  while i > 0 do
    local k = from[i]
    local w = s:sub(k + 1, i)
    table.insert(out, 1, CONTR[w] or w)
    i = k
  end
  return out
end

-- 让结果的大小写跟着输入走：Hel → Hello，HEL → HELLO，hel → hello
function M.sync_case(input, word)
  local first = input:sub(1, 1)
  if not first:match("%a") then return word end
  if first:match("%u") then
    local rest = input:gsub("[^%a]", "")
    if #rest >= 2 and rest == rest:upper() then return word:upper() end
    return word:sub(1, 1):upper() .. word:sub(2)
  end
  return word
end

return M
