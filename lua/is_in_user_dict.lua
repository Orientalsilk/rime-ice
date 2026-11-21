-- 根据是否在用户词典，在 comment 上加上一个星号 *
-- 在 engine/filters 增加 - lua_filter@*is_in_user_dict
-- 在方案里写配置项：
-- is_in_user_dict: true     为输入过的内容加星号 (默认值)
-- is_in_user_dict: false    为未输入过的内容加星号

local M = {}

local is_user = {
    user_table = true,
    user_phrase = true,
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
        local is_current_user_word = is_user[cand.type] or false

        if target_state == is_current_user_word then
            cand.comment = (cand.comment or "") .. '*'
        end

        yield(cand)
    end
end

return M