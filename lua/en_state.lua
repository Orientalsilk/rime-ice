-- 英文模式的「光标前面是什么」记录，给自动空格 / 句首大写用（en_mode_processor 写，en_spacer 读）。
-- tail：nil 不知道（删除、移动光标、换行后等）
--       "word" 英文单词   "punct" , ; :   "sent" . ! ?
--       "start" 一段文字的开头（首字母要大写，但前面不用补空格）
--       "space" 空格      "sent_space" 句号后的空格   "newline" 换行
local S = { tail = "start", stamp = os.time() }

function S.reset() S.tail = nil; S.stamp = os.time() end

-- 好一阵没动过（换了输入框、新开一段话）：当作新的开头
function S.check_idle(seconds)
  if seconds and seconds > 0 and os.time() - S.stamp > seconds then
    S.tail = "start"
    S.stamp = os.time()
  end
end

-- 记录一段刚上屏 / 刚输入的文字
function S.note_text(text)
  if not text or text == "" then return end
  S.stamp = os.time()
  local last = text:sub(-1)
  -- 中文句末标点（。！？）：后面的英文要大写，但不用补空格
  if text:match("。$") or text:match("！$") or text:match("？$") then
    S.tail = "sent_space"
    return
  end
  if last == "\n" then
    S.tail = "newline"
  elseif last:match("%s") then
    if text:match("[%.!%?]%s+$") or S.tail == "sent" or S.tail == "sent_space" or S.tail == "newline" then
      S.tail = (S.tail == "newline" and #text == 1) and "newline" or "sent_space"
    else
      S.tail = "space"
    end
  elseif last:match("[%.!%?]") then
    S.tail = "sent"
  elseif last:match("[,;:]") then
    S.tail = "punct"
  elseif last:match("[%a']") or last:match("%d") then
    S.tail = "word"
  else
    S.tail = nil
  end
end

-- 记录一个不经过候选的按键（空格、标点、回车等）；ch 是字符
function S.note_key(ch)
  S.stamp = os.time()
  if ch == " " then
    if S.tail == "sent" or S.tail == "sent_space" then S.tail = "sent_space"
    elseif S.tail == "newline" then S.tail = "newline"
    else S.tail = "space" end
  elseif ch == "\n" then
    S.tail = "newline"
  elseif ch:match("[%.!%?]") then
    S.tail = "sent"
  elseif ch:match("[,;:]") then
    S.tail = "punct"
  else
    S.tail = nil
  end
end

function S.needs_space()
  return S.tail == "word" or S.tail == "punct" or S.tail == "sent"
end

function S.needs_cap()
  return S.tail == "sent" or S.tail == "sent_space" or S.tail == "newline" or S.tail == "start"
end

return S
