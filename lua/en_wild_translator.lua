-- 英文模式下的三个查词功能（词表见 en_words.txt）：
--   1. 通配符：be*ful  →  beautiful、bashful…（* 代表任意多个字母，_ 代表一个字母）
--   2. 词性筛选：auto~n  →  auto 开头、词性是名词的词；~v 动词，~a 形容词，~ad 副词，
--      ~vt/~vi 及物/不及物动词，~prep 介词，~conj 连词，~pron 代词
--   3. 连写拆词：ilovelua  →  i love lua（输入的不是一个词、但能拆成几个词时给出）
-- 用法：translators 里加  - lua_translator@*en_wild_translator

local Words = require("en_words")

local MAX = 12
local POS = {
  n = "n", v = "v", a = "a", adj = "a", ad = "ad", adv = "ad", vt = "vt", vi = "vi",
  prep = "prep", conj = "conj", pron = "pron", art = "art", int = "interj", interj = "interj",
  pl = "pl", abbr = "abbr",
}

local function make(text, comment, seg)
  local c = Candidate("en_wild", seg.start, seg._end, text, "")
  if comment and comment ~= "" then c.comment = " " .. comment end
  -- 普通通配符候选保持较高权重；连写拆词只作辅助候选，避免压过完整词。
  local quality = (comment == "连写拆词") and 20 or 80
  pcall(function() c.quality = quality end)
  return c
end

local function to_pattern(q)
  -- q 里只有 字母 ' * _ ，转成 Lua 匹配式
  local p = q:lower():gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
  p = p:gsub("%*", "[%%a']*"):gsub("_", "[%%a']")
  return p
end

local function func(input, seg, env)
  local ctx = env.engine.context
  if not ctx:get_option("en_mode") then return end
  local q = input:sub(seg.start + 1, seg._end)
  if q == "" then return end

  -- 网址 / 邮箱：原样给一个候选；接在单词后面时前面补空格
  if seg:has_tag("en_url") then
    local S = require("en_state")
    S.check_idle(60)
    local c = Candidate("en_url", seg.start, seg._end, (S.needs_space() and " " or "") .. q, "")
    c.comment = q:find("@", 1, true) and " 〔邮箱〕" or " 〔网址〕"
    pcall(function() c.quality = 100 end)
    yield(c)
    return
  end

  -- 连字符词：well-known、well-kn、covid-19、e-mail
  if seg:has_tag("en_hyph") then
    local prefix, last = q:match("^(.*%-)([^%-]*)$")
    if not prefix then return end
    local function cand(text, comment, quality)
      local c = Candidate("en_hyph", seg.start, seg._end, text, "")
      if comment and comment ~= "" then c.comment = " " .. comment end
      pcall(function() c.quality = quality end)
      return c
    end
    local raw = q
    local low = last:lower()
    if last == "" or not last:match("^%a[%a']*$") then
      yield(cand(raw, "", 100))   -- 空 / 数字结尾：原样
      return
    end
    local function gloss_of(w)
      local r = Words.search(w, "^(" .. w:gsub("[%^%$%(%)%%%.%[%]%+%-%?%*]", "%%%0") .. ")\t([^\n]*)", nil, 1)
      return r[1] and r[1][2] or ""
    end
    local known = Words.is_word(low)
    local seen = {}
    local function add(text, comment, quality)
      if seen[text] then return end
      seen[text] = true
      yield(cand(text, comment, quality))
    end
    if known then add(raw, gloss_of(low), 100) end
    local rs = Words.search(low, "^(" .. to_pattern(low) .. "[%a']*)\t([^\n]*)", nil, MAX)
    for i, r in ipairs(rs) do
      add(prefix .. Words.sync_case(last, r[1]), r[2], 99 - i * 0.01)
    end
    add(raw, "", known and 99 or 98)
    return
  end

  if seg:has_tag("en_wild") then
    local body, pos = q:match("^([%a'*_]*)~(%a+)$")
    local pos_pat
    if pos then
      local key = POS[pos:lower()]
      if not key then return end
      pos_pat = "%f[%a]" .. key .. "%."
      q = body
      if not q:find("[*_]") then q = q .. "*" end  -- 没写通配符时，当作「以此开头」
    elseif q:find("~", 1, true) then
      return
    end
    local lit = q:lower():match("^[%a']+")  -- 词开头那段固定的字母
    if not lit then return end
    local pat = "^(" .. to_pattern(q) .. ")\t([^\n]*)"
    for _, r in ipairs(Words.search(lit, pat, pos_pat, MAX)) do
      yield(make(Words.sync_case(q, r[1]), r[2], seg))
    end
    return
  end

  -- 连写拆词：普通字母串与包含撇号的英文缩写分开处理。
  -- 不把未知撇号串直接删掉撇号再拆，避免把 it's 错拆成 its。
  if #q >= 6 and q:match("^[%a']+$") and seg:has_tag("abc") then
    local low = q:lower()
    local has_apostrophe = low:find("'", 1, true) ~= nil

    -- 没有撇号且本身就是有效单词时，不提供可能误导的拆词候选。
    if not has_apostrophe and (Words.cost_table()[low] or Words.is_word(low)) then return end

    -- 带撇号：任何「词 + 's / 't / 're / 've / 'll / 'd / 'm」都认（人名所有格 lily'sbook 也行），
    -- 撇号前面的词不在词表里（人名、isn、don 之类）就原样保留。
    local parts
    if has_apostrophe then
      local PRON = {}
      for w in ("i you he she we they it who that what there here how where when why this these those one"):gmatch("%a+") do PRON[w] = true end
      local SUF = { "s", "t", "re", "ve", "ll", "d", "m" }
      local out, pos, ok = {}, 1, true
      while pos <= #low do
        local run = low:match("^%a*", pos)
        local after = low:sub(pos + #run, pos + #run)
        if after == "'" then
          if #run == 0 then ok = false; break end
          local from = pos + #run + 1
          local suf
          for _, sf in ipairs(SUF) do
            local allowed = (sf == "s") or (sf == "t" and run:sub(-1) == "n") or
              (sf ~= "s" and sf ~= "t" and PRON[run:match("%a+$") and run or ""])
            if allowed and low:sub(from, from + #sf - 1) == sf then
              local rest = low:match("^%a*", from + #sf)
              local nxt = low:sub(from + #sf + #rest, from + #sf + #rest)
              if (rest == "" or Words.is_word(rest) or Words.split(rest)) and (nxt == "" or nxt == "'") then
                suf = sf
                break
              end
            end
          end
          local head = Words.is_word(run) and { run } or (Words.split(run) or { run })
          if suf then
            head[#head] = head[#head] .. "'" .. suf
            pos = from + #suf
          elseif run:sub(-1) == "s" then
            -- 复数所有格：johns'book → johns' book
            head[#head] = head[#head] .. "'"
            pos = from
          else
            ok = false; break
          end
          for _, h in ipairs(head) do out[#out + 1] = h end
        else
          if #run == 0 then break end
          local tail = Words.is_word(run) and { run } or (Words.split(run) or { run })
          for _, h in ipairs(tail) do out[#out + 1] = h end
          pos = pos + #run
        end
      end
      if ok and #out >= 2 then parts = out end
    end

    -- 纯字母连写：沿用词库拆分；带撇号的未知串绝不删掉撇号猜测。
    if not parts and not has_apostrophe then
      local split = Words.split(low)
      if split and #split >= 2 then parts = split end
    end

    if parts and #parts >= 2 then
      local text = table.concat(parts, " ")
      local letters = q:gsub("[^%a]", "")
      if #letters > 1 and letters == letters:upper() then
        text = text:upper()
      elseif q:match("^[A-Z]") then
        text = text:gsub("^%l", string.upper)
      end
      yield(make(text, "连写拆词", seg))
    end
  end
end

return func
