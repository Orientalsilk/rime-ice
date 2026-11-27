-- 双拼里精准识别英文，让英文候选及时、靠前出现。
-- 判断依据：双拼每两个字母是一个音节。输入里只要有一对字母拼不出任何音节，
-- 就说明不可能是双拼，而是英文。这样连打整句双拼时不会被误当成英文。
-- 规则（可在 double_pinyin_mspy.schema.yaml 的 en_boost 里调整）：
--   1. 输入不可能是双拼，且恰好是词库里的一个英文单词（长度 >= min_len），英文排到最前；
--      reduce_english_filter/words 里列出的短词除外。
--   2. 输入不可能是双拼，长度 >= prefix_min_len，且是某些英文单词的开头，
--      这些英文单词（最多 prefix_count 个）也排到前面。
--   3. xxx's / xxx't / xxx're / xxx'll / xxx've / xxx'd / xxx'm 这种缩写，
--      不管词库有没有，都原样给出（如 leslie's）。
--   4. 能拼成双拼的输入（如整句双拼），汉字照常排前面；英文只在后面补几个「以它开头的常用词」
--      （soft_count 个，3 个字母起），不抢汉字位置，也不会一下子冒出几百个候选。
--   5. 英文模式（en_mode）下：整词 + 最多 en_prefix_count 个补全，从第 1 个字母起。
-- 补全不再由 table_translator 一次性铺开，而是这里限量给，打字更跟手。

local valid_pairs = {}
for code in ("aa ah ai aj ak al an ao b; ba bc bd bf bg bh bi bj bk bl bm bn bo bs bu bx bz ca cb ce cf cg ch ci cj ck cl co cp cr cs cu cv cz d; da db dc de df dg dh di dj dk dl dm dn do dp dq dr ds du dv dw dx dz ee ef eg ei en er ez fa fb fc ff fg fh fj fo fu fz ga gb gd ge gf gg gh gj gk gl go gp gr gs gu gv gw gy gz ha hb hd he hf hg hh hj hk hl hm ho hp hr hs hu hv hw hy hz ia ib id ie if ig ih ii ij ik il io ip ir is iu iv iw iy j; jc jd ji jm jn jp jq jr js jt ju jv jw jx ka kb kd ke kf kg kh kj kk kl ko kp kr ks ku kv kw ky kz l; la lb lc ld le lf lg lh li lj lk ll lm ln lo lp lq lr ls lt lu lv lw lx lz m; ma mb mc me mf mg mh mi mj mk ml mm mn mo mq mu mx mz n; na nb nc nd ne nf ng nh ni nj nk nl nm nn no np nq nr ns nt nu nv nw nx nz oa ob oe of og oh oj ok ol oo or ou oz p; pa pb pc pf pg ph pi pj pk pl pm pn po pu px pz q; qc qd qi qm qn qp qq qr qs qt qu qv qw qx rb re rf rg rh ri rj rk ro rp rr rs ru rv rw sa sb se sf sg sh si sj sk sl so sp sr ss su sv t; ta tb tc te tg th ti tj tk tl tm to tp tr ts tu tv tx tz ua ub ud ue uf ug uh ui uj uk ul uo up ur uu uv uw uy uz va vb vd ve vf vg vh vi vj vk vl vo vp vr vs vu vv vw vy vz wa wf wg wh wj wl wo ws wu wz x; xc xd xi xm xn xp xq xr xs xt xu xv xw xx y; ya yb ye yh yi yj yk yn yo yp yr ys yt yu yv za zb ze zf zg zh zi zj zk zl zo zp zr zs zu zv zz ńg ňg ǹg"):gmatch("%S+") do valid_pairs[code] = true end

local contractions = { s = true, t = true, re = true, ll = true, ve = true, d = true, m = true }

-- 输入是否有可能是双拼：每两个字母都能拼出音节（末尾多出的一个字母算正在输入，放行）
local function could_be_double_pinyin(input)
  local s = input:lower()
  for i = 1, #s - 1, 2 do
    if not valid_pairs[s:sub(i, i + 1)] then return false end
  end
  return true
end

local function set_quality(c, q)
  pcall(function() c.quality = q end)
  return c
end

local function init(env)
  local config = env.engine.schema.config
  env.min_len = config:get_int("en_boost/min_len") or 4
  env.prefix_min_len = config:get_int("en_boost/prefix_min_len") or 5
  env.prefix_count = config:get_int("en_boost/prefix_count") or 5
  env.quality = config:get_double("en_boost/quality") or 60
  env.soft_count = config:get_int("en_boost/soft_count") or 4
  env.soft_quality = config:get_double("en_boost/soft_quality") or 1.05
  env.en_prefix_count = config:get_int("en_boost/en_prefix_count") or 8

  env.skip = {}
  local list = config:get_list("reduce_english_filter/words")
  if list then
    for i = 0, list.size - 1 do
      local v = list:get_value_at(i)
      if v then env.skip[v:get_string():lower()] = true end
    end
  end

  -- 常用词库（带补全）：只用来取「以输入开头的词」，不挂在引擎里
  local ok, tran = pcall(Component.Translator, env.engine, env.engine.schema, "", "table_translator@english_pre")
  env.tran = ok and tran or nil
  -- 完整词库（只做整词匹配），生僻词也能提前
  local ok2, tran2 = pcall(Component.Translator, env.engine, env.engine.schema, "", "table_translator@english_exact")
  env.tran_exact = ok2 and tran2 or nil
end

-- 整词匹配：返回词库里与输入完全相同的那一个候选
local function find_exact(env, input, seg)
  local t = env.tran_exact or env.tran
  if not t then return nil end
  local tx = t:query(input, seg)
  if not tx then return nil end
  for cand in tx:iter() do
    if cand.text == input then return cand end
  end
  return nil
end

-- 以输入开头的常用词（不含输入本身），最多 count 个，权重依次略降
local function yield_prefix(env, input, seg, count, base_quality)
  if not env.tran then return end
  local tr = env.tran:query(input, seg)
  if not tr then return end
  local shown, scanned = 0, 0
  for cand in tr:iter() do
    scanned = scanned + 1
    if cand.text ~= input then
      shown = shown + 1
      yield(set_quality(Candidate(cand.type, cand.start, cand._end, cand.text, cand.comment), base_quality - shown * 0.0001))
    end
    if shown >= count or scanned >= 40 then break end
  end
end

local function func(input, seg, env)
  -- 缩写：leslie's
  local base, suf = input:match("^(%a+)'(%a+)$")
  if base and contractions[suf:lower()] then
    yield(set_quality(Candidate("table", seg.start, seg._end, input, ""), env.quality))
    return
  end

  -- 全大写输入（HTTP、HELLO）：大小写跟着输入走。输入本身排第一，再给出以它开头的单词（大写）
  if #input >= 2 and input:match("^%u[%u]+$") and env.tran then
    yield(set_quality(Candidate("table", seg.start, seg._end, input, ""), env.quality))
    if #input >= 3 then
      local tr = env.tran:query(input:lower(), seg)
      if tr then
        local shown, scanned = 0, 0
        for cand in tr:iter() do
          scanned = scanned + 1
          local up = cand.text:upper()
          if up ~= input and cand.text:match("^%l[%l']*$") then
            shown = shown + 1
            yield(set_quality(Candidate(cand.type, cand.start, cand._end, up, cand.comment), env.quality - shown * 0.01))
          end
          if shown >= env.prefix_count or scanned >= 30 then break end
        end
      end
    end
    return
  end

  if not input:match("^%a+$") then return end
  local n = #input

  -- 英文模式：整词 + 补全，从第 1 个字母起
  if env.engine.context:get_option("en_mode") then
    local ex = find_exact(env, input, seg)
    if ex then
      yield(set_quality(Candidate(ex.type, ex.start, ex._end, ex.text, ex.comment), env.quality))
    end
    yield_prefix(env, input, seg, env.en_prefix_count, env.quality - 1)
    return
  end

  -- 中英混输
  if n < 3 then return end
  if env.skip[input:lower()] then return end

  if could_be_double_pinyin(input) then
    -- 可能是双拼：汉字照常排前面，英文只在后面补几个开头相同的常用词
    yield_prefix(env, input, seg, env.soft_count, env.soft_quality)
    return
  end

  -- 不可能是双拼，一定是英文：整词提前；够长时补全也提前
  if n >= env.min_len then
    local ex = find_exact(env, input, seg)
    if ex then
      yield(set_quality(Candidate(ex.type, ex.start, ex._end, ex.text, ex.comment), env.quality))
    end
  end
  if n >= env.prefix_min_len then
    yield_prefix(env, input, seg, env.prefix_count, env.quality - 1)
  end
end

return { init = init, func = func }
