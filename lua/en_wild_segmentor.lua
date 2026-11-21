-- 英文模式下，输入里出现通配符 * _ 或词性标记 ~ 时，把整段输入标成「英文查词」，
-- 交给 en_wild_translator 处理（否则 * ~ 会被当成标点切开）。
-- 用法：segmentors 里放最前面  - lua_segmentor@*en_wild_segmentor

local function func(segs, env)
  local ctx = env.engine.context
  if not ctx:get_option("en_mode") then return true end
  local pos = segs:get_current_start_position()
  local rest = segs.input:sub(pos + 1)
  local tag, prompt
  if rest ~= "" and (rest:match("^https?:[^%s]*$") or rest:match("^www%.[^%s]*$")
      or rest:match("^[%w._%-+]+@[^%s]*$")) then
    tag, prompt = "en_url", "(网址/邮箱)"
  elseif rest ~= "" and rest:match("^%a[%a'*_~]*$") and rest:match("[*_~]") then
    tag, prompt = "en_wild", "(查词)"
  elseif rest ~= "" and rest:match("^%a[%w']*%-[%w'%-]*$") then
    tag, prompt = "en_hyph", "(连字符)"
  else
    return true
  end
  local seg = Segment(pos, segs.input:len())
  local ok = pcall(function() seg.tags = Set({ tag }) end)
  if not ok then pcall(function() seg.tags = seg.tags + Set({ tag }) end) end
  seg.prompt = prompt
  segs:add_segment(seg)
  return false  -- 整段已经处理，不再交给后面的分段器
end

return func
