-- 词条隐藏、降频（流式输出版：不再一次性缓冲 180 个候选，输入更流畅）
-- 在 engine/processors 增加 - lua_processor@*cold_word_drop.processor
-- 在 engine/filters 增加 - lua_filter@*cold_word_drop.filter
-- 在 key_binder 增加快捷键：
-- reduce_freq_cand: "Control+j"  # 匹配当前输入码后隐藏指定的候选字词 或候选词条放到第四候选位置
-- drop_cand: "Control+d"       # 强制删词, 无视输入的编码

local filter = {}

local function find_index(list, v)
    for i = 1, #list do
        if list[i] == v then return i end
    end
end

function filter.init(env)
    local config = env.engine.schema.config
    local _sd, drop_words = pcall(require, "cold_word_drop/drop_words")
    local _sh, hide_words = pcall(require, "cold_word_drop/hide_words")
    local _st, turn_down_words = pcall(require, "cold_word_drop/turn_down_words")
    local _sr, reduce_freq_words = pcall(require, "cold_word_drop/reduce_freq_words")
    env.word_reduce_idx = config:get_int("cold_word_reduce/idx") or 4
    env.drop_words = _sd and drop_words or {}
    env.hide_words = _sh and hide_words or {}
    env.reduce_freq_words = (_st and turn_down_words) or (_sr and reduce_freq_words) or {}
    env.drop_set, env.drop_n = {}, -1
end

function filter.func(input, env)
    -- 删词表有增加时（processor 追加）自动重建集合，查找由线性扫描变成 O(1)
    local drop_words = env.drop_words
    if #drop_words ~= env.drop_n then
        local set = {}
        for _, w in ipairs(drop_words) do set[w] = true end
        env.drop_set, env.drop_n = set, #drop_words
    end
    local drop_set = env.drop_set
    local hide_words = env.hide_words
    local reduce = env.reduce_freq_words

    -- 前 slots 个位置留给正常候选，被降频的词暂存，等前几位排满后再输出
    local slots = env.word_reduce_idx - 1
    local held = {}

    local function flush()
        for i = 1, #held do yield(held[i]) end
        held = {}
    end

    for cand in input:iter() do
        local text = cand.text:gsub(" ", "")
        local code = cand.preedit:gsub(" ", "")
        if slots > 0 then
            local rl = reduce[text]
            if rl and find_index(rl, code) then
                held[#held + 1] = cand
            elseif not (drop_set[text] or (hide_words[text] and find_index(hide_words[text], code))) then
                yield(cand)
                slots = slots - 1
                if slots == 0 then flush() end
            end
        elseif not (drop_set[text] or (hide_words[text] and find_index(hide_words[text], code))) then
            yield(cand)
        end
    end
    flush()
end

return filter
