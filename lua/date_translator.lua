-- 日期时间，可在方案中配置触发关键字。

local convert_num = require("convert_ar_num_to_zh").convert
local convert_digits = require("convert_ar_num_to_zh").digits

-- 提高权重的原因：因为在方案中设置了大于 1 的 initial_quality，导致 rq sj xq dt ts 产出的候选项在所有词语的最后。
local function yield_cand(seg, text)
    local cand = Candidate('', seg.start, seg._end, text, '')
    cand.quality = 100
    yield(cand)
end

local M = {}

-- 自定义格式字符串解析：支持 Y y m n d j H M S I P p T 等占位符，
-- 其余字符（- / . : 空格 年 月 日 等）原样保留。
-- A 是"早上/中午/下午/晚上/凌晨"这个时段文字，O 是 ISO 8601 时区偏移（如 +08:00）
local function format_date(fmt, t, period_name, iso_tz)
    local month = tonumber(os.date('%m', t))
    local day = tonumber(os.date('%d', t))
    local tokens = {
        Y = os.date('%Y', t),
        y = os.date('%y', t),
        m = os.date('%m', t),
        n = tostring(month),
        d = os.date('%d', t),
        j = tostring(day),
        H = os.date('%H', t),
        M = os.date('%M', t),
        S = os.date('%S', t),
        I = os.date('%I', t),
        P = os.date('%p', t),
        p = os.date('%p', t):lower(),
        A = period_name or '',
        O = iso_tz or '',
    }
    return (fmt:gsub('.', function(c)
        return tokens[c] or c
    end))
end

-- 配置里没写 date_formats / time_formats / datetime_formats 时使用的默认格式，
-- 和原来写死在代码里的那几种保持一致
local default_date_formats = { "Y-m-d", "Y/m/d", "Y.m.d", "Ymd", "Y年m月d日" }
local default_time_formats = { "H:M", "H:M:S", "AI:M", "I:M P" }
local default_datetime_formats = { "Y-m-dTH:M:S O", "Y-m-d H:M:S", "YmdHMS" }

-- 从配置读取一个字符串列表；配置里没有这一项时返回默认表
local function get_format_list(config, path, default_list)
    local list = config:get_list(path)
    if not list or list.size == 0 then
        return default_list
    end
    local result = {}
    for i = 0, list.size - 1 do
        result[#result + 1] = list:get_value_at(i).value
    end
    return result
end

-- 月份名称表
local month_names_short = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local month_names_long = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December" }

function M.init(env)
    local config = env.engine.schema.config
    env.name_space = env.name_space:gsub('^*', '')
    -- 修复：触发词存到 env 而非模块级 M —— 雾凇拼音(全拼) rime_ice 和微软双拼
    -- double_pinyin_mspy 两个 schema 共用这份 lua 代码，但触发词不同（双拼版
    -- 改成了 rq/sj 等），存在 M 上会导致后加载的 schema 把先加载的覆盖掉，
    -- 切换方案后触发词可能对不上。
    env.date = config:get_string(env.name_space .. '/date') or 'rq'
    env.time = config:get_string(env.name_space .. '/time') or 'sj'
    env.week = config:get_string(env.name_space .. '/week') or 'xq'
    env.datetime = config:get_string(env.name_space .. '/datetime') or 'dt'
    env.timestamp = config:get_string(env.name_space .. '/timestamp') or 'ts'
    env.date_zh = config:get_string(env.name_space .. '/datezh') or 'rqzh'
    env.date_en = config:get_string(env.name_space .. '/dateen') or 'rqen'

    -- 自定义输出格式列表；schema 里没配置的话用默认格式
    env.date_formats = get_format_list(config, env.name_space .. '/date_formats', default_date_formats)
    env.time_formats = get_format_list(config, env.name_space .. '/time_formats', default_time_formats)
    env.datetime_formats = get_format_list(config, env.name_space .. '/datetime_formats', default_datetime_formats)
end

function M.func(input, seg, env)
    -- 日期
    if (input == env.date) then
        local current_time = os.time()
        for _, fmt in ipairs(env.date_formats) do
            yield_cand(seg, format_date(fmt, current_time))
        end

        -- 时间
    elseif (input == env.time) then
        local current_time = os.time()

        local hour = tonumber(os.date("%H", current_time))
        local period_name

        -- 时间段划分（可根据生活习惯自定义）
        if hour >= 5 and hour < 11 then
            period_name = "早上"
        elseif hour >= 11 and hour < 13 then
            period_name = "中午"
        elseif hour >= 13 and hour < 18 then
            period_name = "下午"
        elseif hour >= 18 and hour < 24 then
            period_name = "晚上"
        else
            period_name = "凌晨"
        end

        for _, fmt in ipairs(env.time_formats) do
            yield_cand(seg, format_date(fmt, current_time, period_name))
        end

        -- 星期
    elseif (input == env.week) then
        local current_time = os.time()
        local week_tab = { '日', '一', '二', '三', '四', '五', '六' }
        local text = week_tab[tonumber(os.date('%w', current_time) + 1)]
        yield_cand(seg, '星期' .. text)
        yield_cand(seg, '礼拜' .. text)
        yield_cand(seg, '周' .. text)

        -- ISO 8601/RFC 3339 的时间格式
    elseif (input == env.datetime) then
        local current_time = os.time()

        -- 获取偏移量，例如 "+0800" 或 "+0000"
        local tz = os.date("%z", current_time)

        -- 格式化时区
        -- 如果是零时区 (+0000/-0000)，根据规范输出 "Z"
        -- 否则将 "+0800" 转换为 "+08:00"
        local iso_tz = (tz == "+0000" or tz == "-0000")
            and "Z"
            or tz:gsub("(%d%d)$", ":%1")

        for _, fmt in ipairs(env.datetime_formats) do
            yield_cand(seg, format_date(fmt, current_time, nil, iso_tz))
        end

        -- 时间戳（十位数，到秒，示例 1650861664）
    elseif (input == env.timestamp) then
        local current_time = os.time()
        yield_cand(seg, string.format('%d', current_time))

        -- 中文日期
    elseif (input == env.date_zh) then
        local current_time = os.time()
        local year_0 = convert_digits(tonumber(os.date('%Y', current_time)), true)
        local year_zero = convert_digits(tonumber(os.date('%Y', current_time)), false)
        local month = convert_num(tonumber(os.date('%m', current_time)))
        local day = convert_num(tonumber(os.date('%d', current_time)))

        yield_cand(seg, string.format('%s年%s月%s日', year_0, month, day))
        yield_cand(seg, string.format('%s年%s月%s日', year_zero, month, day))
        yield_cand(seg, os.date('%Y年%m月%d日', current_time):gsub('年0', '年'):gsub('月0', '月'))

        -- 英文日期
    elseif (input == env.date_en) then
        local current_time = os.time()
        local day = tonumber(os.date("%d", current_time))
        local month = tonumber(os.date("%m", current_time))
        local year = os.date("%Y", current_time)
        -- 计算日期序数后缀
        -- local suffix = "th"
        -- if day % 10 == 1 and day ~= 11 then
        --     suffix = "st"
        -- elseif day % 10 == 2 and day ~= 12 then
        --     suffix = "nd"
        -- elseif day % 10 == 3 and day ~= 13 then
        --     suffix = "rd"
        -- end

        yield_cand(seg, string.format("%d %s %s", day, month_names_long[month], year))  -- en_UK
        yield_cand(seg, string.format("%s %d, %s", month_names_long[month], day, year)) -- en_US
    end

    -- -- 显示内存
    -- local cand = Candidate("date", seg.start, seg._end, ("%.f"):format(collectgarbage('count')), "")
    -- cand.quality = 100
    -- yield(cand)
    -- if input == "xxx" then
    --     collectgarbage()
    --     local cand = Candidate("date", seg.start, seg._end, "collectgarbage()", "")
    --     cand.quality = 100
    --     yield(cand)
    -- end
end

return M
