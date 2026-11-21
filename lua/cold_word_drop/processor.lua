-- 词条隐藏、降频
-- 在 engine/processors 增加 - lua_processor@*cold_word_drop.processor
-- 在 engine/filters 增加 - lua_filter@*cold_word_drop.filter
-- 在 key_binder 增加快捷键：
-- reduce_freq_cand: "Control+j"  # 匹配当前输入码后隐藏指定的候选字词 或候选词条放到第四候选位置
-- drop_cand: "Control+d"         # 强制删词, 无视输入的编码
-- get_record_filername() 函数中仅支持了 Windows、macOS、Linux

-- 不再加载 metatable.lua / string.lua：它们会改写全局 type() 并向全局注入函数，拖慢所有脚本
local processor = {}

local function find_index(t, v)
    for i = 1, #t do
        if t[i] == v then return i end
    end
end

local function serialize(v)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local parts = {}
        if #v > 0 then
            for _, x in ipairs(v) do parts[#parts + 1] = "\t" .. serialize(x) end
        else
            for k, x in pairs(v) do parts[#parts + 1] = "\t[" .. serialize(k) .. "] = " .. serialize(x) end
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. ",\n}"
    end
    error("can not serialize a " .. t)
end

local function get_record_filername(record_type)
	local path_sep = "/"
	local user_data_dir = rime_api:get_user_data_dir()
	local user_distribute_name = rime_api:get_distribution_code_name()
	if user_distribute_name:lower():match("weasel") then path_sep = [[\]] end
	if user_distribute_name:lower():match("ibus") then
		return string.format("%s/rime/lua/cold_word_drop/%s_words.lua",
			os.getenv("HOME") .. "/.config/ibus",
			record_type
		)
	else
		local file_path = string.format("%s/lua/cold_word_drop/%s_words.lua", user_data_dir, record_type)
		return file_path:gsub("/", path_sep)
	end
end

local function write_word_to_file(env, record_type)
	local filename = get_record_filername(record_type)
	local record_header = string.format("local %s_words =\n", record_type)
	local record_tailer = string.format("\nreturn %s_words", record_type)
	if not filename then
		return false
	end
	local fd = assert(io.open(filename, "w")) --打开
	-- fd:flush() --刷新
	local x = string.format("%s_list", record_type)
	local record = serialize(env.tbls[x]) -- lua 的 table 对象 序列化为字符串
	fd:setvbuf("line")
	fd:write(record_header) --写入文件头部
	fd:write(record) --写入 序列化的字符串
	fd:write(record_tailer) --写入文件尾部, 结束记录
	fd:close() --关闭
end

local function append_word_to_droplist(env, ctx, action_type)
	local word = ctx.word:gsub(" ", "")
	local input_code = ctx.code:gsub(" ", "")

	if action_type == "drop" then
		table.insert(env.drop_words, word) -- 高亮选中的词条插入到 drop_list
		return true
	end

	if action_type == "hide" then
		if not env.hide_words[word] then
			env.hide_words[word] = { input_code }
			-- 隐藏的词条如果已经在 hide_list 中, 则将输入串追加到 值表中, 如: ['藏'] = {'chang', 'zhang'}
		elseif not find_index(env.hide_words[word], input_code) then
			table.insert(env.hide_words[word], input_code)
		end
		return true
	end

	if action_type == "reduce_freq" then
		if env.reduce_freq_words[word] then
			table.insert(env.reduce_freq_words[word], input_code)
		else
			env.reduce_freq_words[word] = { input_code }
		end
		return true
	end
end

function processor.init(env)
    local engine = env.engine
    local config = engine.schema.config
    local _sd, drop_words = pcall(require, "cold_word_drop/drop_words")
    local _sh, hide_words = pcall(require, "cold_word_drop/hide_words")
    local _st, turn_down_words = pcall(require, "cold_word_drop/turn_down_words")
    local _sr, reduce_freq_words = pcall(require, "cold_word_drop/reduce_freq_words")
    env.drop_words = _sd and drop_words or {}
    env.hide_words = _sh and hide_words or {}
    env.reduce_freq_words = (_st and turn_down_words) or (_sr and reduce_freq_words) or {}
    env.drop_cand_key = config:get_string("key_binder/drop_cand") or "Control+d"
    env.hide_cand_key = config:get_string("key_binder/hide_cand") or "Control+x"
    env.turn_down_cand_key = config:get_string("key_binder/turn_down_cand") or nil
    env.reduce_cand_key = env.turn_down_cand_key or config:get_string("key_binder/reduce_freq_cand") or "Control+j"
    env.tbls = {
		["drop_list"] = env.drop_words,
		["hide_list"] = env.hide_words,
		["reduce_freq_list"] = env.reduce_freq_words,
	}
	-- 快捷键 -> 动作，只在初始化时建一次
	env.action_map = {
		[env.drop_cand_key] = "drop",
		[env.hide_cand_key] = "hide",
		[env.reduce_cand_key] = "reduce_freq",
	}
end

function processor.func(key, env)
    -- 先用按键快速排除，避免每次按键都做多余计算
    local action_type = env.action_map[key:repr()]
    if not action_type then
        return 2
    end
    local context = env.engine.context
    if not context:has_menu() then
        return 2
    end

    local cand = context:get_selected_candidate()
    if not cand then
        return 2
    end
    local ctx_map = {
        ["word"] = cand.text,
        ["code"] = context:get_script_text(),
    }
    local res = append_word_to_droplist(env, ctx_map, action_type)

    context:refresh_non_confirmed_composition() -- 刷新当前输入法候选菜单, 实现看到实时效果
    if not res then
        return 2
    end

    -- 期望被删的词和隐藏的词条写入文件(drop_words.lua, hide_words.lua)
    write_word_to_file(env, action_type)
    return 1 -- kAccept
end

return processor
