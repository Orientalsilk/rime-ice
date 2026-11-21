-- 给"整句自动组句"候选（cand.type == 'sentence'）的 comment 加上 ∞
-- 这是语法模型（librime-octagram / grammar:）真正发挥重排序作用的候选类型；
-- 注意：无法精确判断"某个词是否被语法模型影响过排序"，因为语法模型是在
-- script_translator 内部对所有候选打分重排，不会在候选上留下可读的标记，
-- 这里只能退而求其次，标出"整句自动组句"这一类候选。
--
-- 在 engine/filters 增加 - lua_filter@*grammar_hint
-- 在方案里写配置项（可选，默认为 true）：
-- grammar_hint: true     为整句候选加 ∞ (默认值)
-- grammar_hint: false    为非整句候选加 ∞（一般用不到，保留和 is_in_user_dict 一致的开关风格）

local M = {}

local is_sentence = {
    sentence = true,
}

function M.init(env)
    local config = env.engine.schema.config
    env.name_space = env.name_space:gsub('^%*', '')

    if config:is_null(env.name_space) then
        env.target_state = true
    else
        env.target_state = config:get_bool(env.name_space)
    end
end

function M.func(input, env)
    local target_state = env.target_state
    for cand in input:iter() do
        local is_current_sentence = is_sentence[cand.type] or false

        if target_state == is_current_sentence then
            cand.comment = (cand.comment or "") .. '∞'
        end

        yield(cand)
    end
end

return M
