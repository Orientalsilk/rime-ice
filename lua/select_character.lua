-- 以词定字
-- 原脚本 https://github.com/BlindingDark/rime-lua-select-character
-- 可在 default.yaml → key_binder 下配置快捷键，默认为左右中括号 [ ]
-- 20230526195910 不再错误地获取commit_text，而是直接获取get_selected_candidate().text
-- 20240128141207 重写：将读取设置移动到 init 方法中；简化中文取字方法；预先判断候选存在与否，无候选取 input
-- 20240508111725 当候选字数为 1 时，快捷键使该字上屏
-- 20250515093039 以词定字支持长句输入
-- 20250516231523 当候选字数为 1 且还有未处理的输入时，快捷键使该字上屏, 保留未处理部分
-- 20250524151149 当光标位置不在 input 末尾时,保留光标右侧部分
local select = {}

function select.init(env)
    local config = env.engine.schema.config
    env.first_key = config:get_string('key_binder/select_first_character')
    env.last_key = config:get_string('key_binder/select_last_character')
end

function select.func(key, env)
    local engine = env.engine
    local context = env.engine.context

    -- 先用按键快速排除：非 [ ] 键立即返回，避免每次按键都取候选
    if key:release() then
        return 2
    end
    local repr = key:repr()
    if repr ~= env.first_key and repr ~= env.last_key then
        return 2
    end

    if
        (context:is_composing() or context:has_menu())
        and (env.first_key or env.last_key)
    then
        local input = context.input
        local selected_candidate = context:get_selected_candidate()
        selected_candidate = selected_candidate and selected_candidate.text or input

        -- 修复：候选词为空字符串时，后续 utf8.offset 会返回 nil 导致崩溃，提前放弃处理
        if selected_candidate == "" then
            return 2
        end

        local selected_char
        if (repr == env.first_key) then
            selected_char = selected_candidate:sub(1, utf8.offset(selected_candidate, 2) - 1)
        else
            selected_char = selected_candidate:sub(utf8.offset(selected_candidate, -1))
        end

        local commit_text = context:get_commit_text()
        -- 修复：用 plain=true 做纯字面查找，避免 selected_candidate 中的特殊符号被当作 Lua pattern 解析
        local start_pos, end_pos = commit_text:find(selected_candidate, 1, true)

        -- 修复：理论上不应找不到，但加一层兜底，避免异常状态下 end_pos 为 nil 导致崩溃
        if not start_pos then
            return 2
        end

        local caret_pos = context.caret_pos

        -- 修复：直接按位置切片拼接，而非用 gsub 做模式替换
        -- 原写法在 commit_text 前缀中若存在多个相同子串时会被全部替换，这里只精确改写 find 定位到的这一处
        local part1 = commit_text:sub(1, start_pos - 1) .. selected_char
        local part2 = commit_text:sub(end_pos + 1)

        engine:commit_text(part1)
        context:clear()
        if caret_pos ~= #input then
            part2 = part2 .. input:sub(caret_pos + 1)
        end
        if part2 ~= "" then
            context:push_input(part2)
        end
        return 1
    end
    return 2
end

return select