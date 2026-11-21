-- 长词优先（提升「西安」「提案」「图案」「饥饿」等词汇的优先级）
-- 感谢&参考于： https://github.com/tumuyan/rime-melt
-- 不提升包含英文、数字的候选项
-- 不提升包含 emoji、假名的候选项（通过将此 Lua 放到 simplifier@emoji 前面来实现）

local M = {}

function M.init(env)
    -- 提升 count 个词语，插入到第 idx 个位置，默认 2、4。
    local config = env.engine.schema.config
    env.name_space = env.name_space:gsub("^%*", "")

    env.count = config:get_int(env.name_space .. "/count") or 2
    env.idx = config:get_int(env.name_space .. "/idx") or 4
end

function M.func(input, env)
    local target_count = env.count
    local target_idx = env.idx

    local l = {}
    local firstWordLength = 0 -- 记录第一个候选词的长度，提前的候选词至少要比第一个候选词长
    local done = 0            -- 记录筛选了多少个词条(只提升 count 个词的权重)
    local i = 1

    for cand in input:iter() do
        -- 防御性兜底：非法 utf8 时 utf8.len 返回 nil，用 0 代替避免后续比较崩溃
        local leng = utf8.len(cand.text) or 0

        -- 只以第一个候选项的长度作为参考（用下标判断，而非长度是否有效）
        if i == 1 then
            firstWordLength = leng
        end

        if i < target_idx then
            -- target_idx 之前的候选项原样输出
            yield(cand)
        elseif leng <= firstWordLength or cand.text:find("[%a%d]") then
            -- 不够长，或包含英文/数字，暂存，稍后按原顺序输出
            table.insert(l, cand)
        else
            -- 长词直接提前输出
            yield(cand)
            done = done + 1
        end

        i = i + 1

        -- 找齐了或者 l 太大了，就不找了，一般前 50 个就够了
        if done == target_count or #l > 50 then
            break
        end
    end

    -- 输出被暂存的候选项
    for _, cand in ipairs(l) do
        yield(cand)
    end

    -- 继续消耗剩余的迭代器
    for cand in input:iter() do
        yield(cand)
    end
end

return M