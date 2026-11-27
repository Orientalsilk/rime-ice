-- 英文模式（开关 en_mode）的按键处理，包括：
--   · 切到英文模式时标点自动变英文标点，切回来时恢复；
--   · 热键：单独点按右 Control 切换英文模式；
--   · 工具栏发来的 Ctrl+Shift+7 / Ctrl+Shift+8：进入 / 退出英文模式；
--   · 英文模式下的空格 / 标点 / 回车 / 删除 / 光标键：记录「光标前面是什么」，
--     让下一个单词自动补空格、句首自动大写（见 en_state.lua、en_spacer.lua）；
--   · 英文模式下输入 * _ ~：当作查词用的通配符 / 词性标记（见 en_wild_translator.lua）；
--   · 英文模式下 Tab：把选中的单词补进输入框（Shift+Tab 撤回上一次补齐）。
-- 用法：processors 里加  - lua_processor@*en_mode_processor

local OPTION = "en_mode"
local ASCII_PUNCT_OPTION = "ascii_punct"
local Accepted, Noop = 1, 2

local S = require("en_state")

-- 没有在输入单词时：记录光标前面的内容（中英文模式都记录，自动空格要用）
local function track(kc, ch)
  if kc == 0xff08 or kc == 0xffff or kc == 0xff1b or (kc >= 0xff50 and kc <= 0xff58) then
    -- 退格、Delete、Esc、Home/End/方向键/翻页：光标前面是什么不确定了
    S.reset()
  elseif kc == 0xff0d or kc == 0xff8d then
    S.note_key("\n")
  elseif ch and not ch:match("%a") then
    -- 字母会开始新的输入，不在这里处理
    S.note_key(ch)
  end
end

local P = {}

function P.init(env)
  local ctx = env.engine.context
  env.en_prev_punct = nil
  env.history = {}
  env.cap_latch = false
  -- 切换热键：单独点按一下右 Control（按下后中间没按别的键、松开时切换）。
  -- 想换成别的键，可在 rime.lua 里设 __en_mode_switch_keyrepr = "F4" 之类。
  env.en_mode_switch_keyrepr = __en_mode_switch_keyrepr
  env.ctrl_r_down = false
  env.idle = 60
  pcall(function()
    env.idle = env.engine.schema.config:get_int("en_spacer/idle_reset_seconds") or 60
  end)

  pcall(function()
    local any = ctx:get_option(OPTION) or ctx:get_option("ascii_mode")
    ctx:set_option("en_any", any)
  end)

  local ok, conn = pcall(function()
    return ctx.option_update_notifier:connect(function(c, name)
      -- 空格键上的状态文字用：英文模式 或 En（ascii_mode）任一开着，en_any 就是开
      if name == OPTION or name == "ascii_mode" then
        local any = c:get_option(OPTION) or c:get_option("ascii_mode")
        if c:get_option("en_any") ~= any then c:set_option("en_any", any) end
      end
      if name ~= OPTION then return end
      local now = c:get_option(OPTION)
      if now ~= env.en_last then
        env.en_last = now
        env.cap_latch = false
        env.history = {}
      end
      if now then
        if env.en_prev_punct == nil then env.en_prev_punct = c:get_option(ASCII_PUNCT_OPTION) end
        c:set_option(ASCII_PUNCT_OPTION, true)
      elseif env.en_prev_punct ~= nil then
        c:set_option(ASCII_PUNCT_OPTION, env.en_prev_punct)
        env.en_prev_punct = nil
      end
    end)
  end)
  env.en_conn = ok and conn or nil

  local ok2, conn2 = pcall(function()
    return ctx.commit_notifier:connect(function(c)
      env.history = {}
      env.cap_latch = false
      -- 中英文模式下的上屏都记录，这样从中文切到英文时也知道光标前是什么
      local ok3, t = pcall(function() return c.commit_history:latest_text() end)
      if ok3 and t then
        S.note_text(t)
        if c:get_option(OPTION) then pcall(function() require("en_user").record(t) end) end
      end
    end)
  end)
  env.en_conn2 = ok2 and conn2 or nil
end

function P.fini(env)
  pcall(function() require("en_user").save() end)
  for _, k in ipairs({ "en_conn", "en_conn2" }) do
    if env[k] then
      pcall(function() env[k]:disconnect() end)
      env[k] = nil
    end
  end
end

function P.func(key, env)
  local keyrepr = key:repr()
  local context = env.engine.context
  local kc = key.keycode

  -- 右 Control 点按：按下只记一笔，松开时（期间没按过其它键）才切换，
  -- 这样不会和 Ctrl+字母 之类的组合键、也不会和 Shift 大小写互相干扰
  local is_ctrl_r = (kc == 0xffe4)
  if is_ctrl_r and not env.en_mode_switch_keyrepr then
    if not key:release() then
      env.ctrl_r_down = true
      return Noop
    end
    if env.ctrl_r_down then
      env.ctrl_r_down = false
      if not context:get_option("ascii_mode") then
        context:set_option(OPTION, not context:get_option(OPTION))
        context:refresh_non_confirmed_composition()
        return Accepted
      end
    end
    return Noop
  end
  if not key:release() then env.ctrl_r_down = false end

  -- Trime 按钮发来的 Ctrl+Shift+7 = 进入英文模式，Ctrl+Shift+8 = 退出（与 ascii_mode 无关）
  -- 不同平台上报的字符不同（7 或 &、8 或 *），都接受
  if key:ctrl() and key:shift() then
    local on, off = (kc == 55 or kc == 38), (kc == 56 or kc == 42)
    if on or off then
      if not key:release() then
        context:set_option(OPTION, on)
        context:refresh_non_confirmed_composition()
      end
      return Accepted
    end
  end

  -- Trime「输入中按 Shift」发来的 Ctrl+Shift+9：
  --   中英混输 → 等于按了 ;（双拼里的 ing）
  --   英文模式 → 等于按了 Shift：下一个字母变大写（Trime 输入中没法正常用 Shift，这里代劳）
  if key:ctrl() and key:shift() and (kc == 57 or kc == 40) then
    if not key:release() then
      if context:get_option(OPTION) then
        env.cap_latch = true
      else
        env.engine:process_key(KeyEvent("semicolon"))
      end
    end
    return Accepted
  end

  if context:get_option("ascii_mode") then return Noop end

  -- 热键：切换英文模式
  if env.en_mode_switch_keyrepr and keyrepr == env.en_mode_switch_keyrepr then
    context:set_option(OPTION, not context:get_option(OPTION))
    context:refresh_non_confirmed_composition()
    return Accepted
  end

  if not context:get_option(OPTION) then
    env.cap_latch = false
    -- 中英混输：只记录光标前面是什么（给英文词自动空格用）
    if not key:release() and not key:ctrl() and not key:alt() and not context:is_composing() then
      track(kc, (kc >= 32 and kc < 127) and string.char(kc) or nil)
    end
    return Noop
  end
  if key:release() or key:ctrl() or key:alt() then return Noop end

  -- 大写锁存：按过「输入中的 Shift」后，下一个字母大写
  if env.cap_latch and not (kc >= 0xffe1 and kc <= 0xffee) then
    env.cap_latch = false
    if kc >= 97 and kc <= 122 and context:is_composing() then
      context:push_input(string.char(kc - 32))
      return Accepted
    end
  end
  local composing = context:is_composing()
  local ch = (kc >= 32 and kc < 127) and string.char(kc) or nil

  -- 网址 / 邮箱：打到 www. / http: / xxx@ 之后，. : / - _ ? = & # % + ~ @ 和数字都当作网址的一部分，
  -- 留在输入框里不拆开（否则 www.baidu.com 会被拆成 Www Baidu Com）；空格上屏整串
  if composing and ch then
    local inp = context.input
    local urlish = inp:match("^https?:") or inp:match("^www%.") or inp:find("@", 1, true)
    local starts = (ch == "." and inp == "www") or (ch == ":" and (inp == "http" or inp == "https"))
      or (ch == "@" and inp:match("^%a+$"))
    if (urlish and ch:match("[%w@%.:/_%-%?=&#%%%+~]")) or starts then
      context:push_input(ch)
      return Accepted
    end
  end

  -- 连字符：英文模式下，字母或数字后面的 - 当作单词的一部分（well-known、covid-19、e-mail），
  -- 不再当翻页键；数字跟在连字符后面时也留在输入框里
  if composing and ch and context.input:match("^%a") then
    local inp = context.input
    if (ch == "-" and inp:match("[%w]$")) or (ch:match("%d") and inp:find("%-[%w']*$")) then
      context:push_input(ch)
      return Accepted
    end
  end

  -- 通配符 / 词性标记：正在输入单词时，* _ ~ 直接进输入框
  if composing and (kc == 42 or kc == 95 or kc == 126) then
    context:push_input(string.char(kc))
    return Accepted
  end

  if composing then
    -- 删除到空 / Esc：清掉大写锁存和 Tab 记录
    if kc == 0xff08 and #context.input <= 1 or kc == 0xff1b then
      env.cap_latch = false
      env.history = {}
      return Noop
    end
    -- 回车：把打的字母原样上屏。原样上屏不经过候选，自动空格接管不到，
    -- 所以在这里补：光标前面是单词 / 逗号 / 句号时，前面补一个空格
    if (kc == 0xff0d or kc == 0xff8d) and context.input:match("^%a[%w'%-]*$") then
      S.check_idle(env.idle)
      local raw = context.input
      env.engine:commit_text((S.needs_space() and " " or "") .. raw)
      S.note_text(raw)
      context:clear()
      return Accepted
    end
    -- 标点：先把当前选中的词上屏，再让标点自己出去；记下「光标前是标点」
    if ch and ch:match("[%.,!%?;:]") then
      context:commit()
      S.note_key(ch)
      return Noop
    end
    -- Tab：把选中的单词补进输入框，方便继续补全或改动；Shift+Tab 撤回
    if kc == 0xff09 and not key:shift() and context:has_menu() then
      local cand = context:get_selected_candidate()
      if cand then
        local g = cand
        pcall(function() g = cand:get_genuine() end)
        local word = (g.text or cand.text):match("^%s*([%a']+)%s*$")
        if word then
          table.insert(env.history, context.input)
          context.input = word
          return Accepted
        end
      end
    end
    if (kc == 0xfe20 or (kc == 0xff09 and key:shift())) and #env.history > 0 then
      context.input = table.remove(env.history)
      return Accepted
    end
    return Noop
  end

  track(kc, ch)

  return Noop
end

return { init = P.init, func = P.func, fini = P.fini }
