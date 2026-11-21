-- Copyright (C) [Mirtle](https://github.com/mirtlecn)
-- 使用说明：<https://github.com/mirtlecn/rime-radical-pinyin/blob/master/search.lua.md>
--
-- 增强（吸收 super_lookup 思路）：
-- 1. 反查编码变体展开（原始码 / 奇位简码 / jv↔ju 互换 / projection 投影）
-- 2. 简单 db 反查结果缓存，减少重复 ReverseLookup 调用

-- 处理 lua 中的特殊字符用于匹配
local function alt_lua_punc( s )
    if s then
        return s:gsub( '([%.%+%-%*%?%[%]%^%$%(%)%%])', '%%%1' )
    else
        return ''
    end
end

-- 获取指定字符在文本中的位置
local function get_pos( text, char )
    local pos = {}
    if text:find( char ) then
        local tmp = text
        for i = 1, utf8.len( tmp ) do
            local first_char = tmp:sub( 1, utf8.offset( tmp, 2 ) - 1 )
            if first_char == char then pos[i] = true end
            tmp = tmp:gsub( '^' .. first_char, '' )
        end
    end
    return pos
end

-- 此函数用于手动写入用户词库，目前仅对双拼有效
local function update_dict_entry( s, code, mem, proj )
    if #s == 0 or utf8.len( s ) == #s or (#code % 2 ~= 0) then
        log.info( '[search.lua]: Ignored' .. s )
        return 0
    end
    local e = DictEntry()
    s = s:gsub( '^%s+', '' ):gsub( '%s+$', '' )
    e.text = s

    local pos = {}
    if s:find( '·' ) and (utf8.len( s ) > 1) then pos = get_pos( s, '·' ) end

    local custom_code = {}
    local loop = 1
    for i = 1, #code, 2 do
        local code_convert = code:sub( i, i + 1 )
        local p = proj:apply( code_convert, true )
        if p and #p > 0 then code_convert = p end
        if code_convert ~= 'dian' or not pos[loop] then
            table.insert( custom_code, code_convert )
        end
        loop = loop + 1
    end

    e.custom_code = table.concat( custom_code, ' ' ) .. ' '
    if mem.start_session then mem:start_session() end
    mem:update_userdict( e, 1, '' )
    if mem.finish_session then mem:finish_session() end
end

local function dict_init( search_string, mem, search_limit, code_projection )
    local dict_table = {}
    if code_projection then
        local p = code_projection:apply( search_string, true )
        if p and #p > 0 then search_string = p end
    end
    if mem:dict_lookup( search_string, true, search_limit ) then
        for entry in mem:iter_dict() do dict_table[entry.text] = true end
    end
    return dict_table
end

local function dict_match( tbl, text )
    if tbl[text] == true then return true end
    return false
end

----------------------------------------------------------------------
-- 编码变体展开（吸收 super_lookup 思路）
----------------------------------------------------------------------

local function add_unique( list, seen, value )
    if value and #value > 0 and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function extract_odd_positions( s )
    if not s or not s:match( '^%l+$' ) or #s % 2 ~= 0 then
        return nil
    end
    local result = ''
    for i = 1, #s, 2 do
        result = result .. s:sub( i, i )
    end
    return result
end

local function get_v_u_variant( s )
    if not s or not s:match( '^%l+$' ) then
        return nil
    end
    local result = s:gsub( '([jqxy])v', '%1u' ):gsub( '([jqxy])u', '%1v' )
    if result ~= s then
        return result
    end
    return nil
end

local function expand_code_variants( part, code_projection )
    local out = {}
    local seen = {}

    add_unique( out, seen, part )

    if part:match( '^%l+$' ) then
        add_unique( out, seen, extract_odd_positions( part ) )
        add_unique( out, seen, get_v_u_variant( part ) )
    end

    if code_projection then
        local projected = code_projection:apply( part, true )
        if projected and #projected > 0 and projected ~= part then
            add_unique( out, seen, projected )
            if projected:match( '^%l+$' ) then
                add_unique( out, seen, extract_odd_positions( projected ) )
                add_unique( out, seen, get_v_u_variant( projected ) )
            end
        end
    end

    return out
end

----------------------------------------------------------------------
-- 反查核心（带缓存 + 变体匹配）
----------------------------------------------------------------------

local function get_cached_codes( text, db_table, cache )
    if cache then
        local hit = cache[text]
        if hit ~= nil then
            return hit
        end
    end

    local codes = {}
    local has_any = false
    for _, db in ipairs( db_table ) do
        local code = db:lookup( text )
        if code and #code > 0 then
            has_any = true
            for part in code:gmatch( '%S+' ) do
                codes[#codes + 1] = part
            end
        end
    end

    local result = has_any and codes or false
    if cache then
        cache[text] = result
        cache._size = (cache._size or 0) + 1
        if cache._size > 3000 then
            for k in pairs( cache ) do
                cache[k] = nil
            end
            cache._size = 0
        end
    end
    return result
end

local function reverse_lookup( code_projection, db_table, wildcard, text, s, global_match, cache )
    if not text or #text == 0 or not s or #s == 0 then
        return false
    end

    local has_wildcard = false
    local pattern_s = s
    if wildcard and s:find( wildcard, 1, true ) then
        pattern_s = s:gsub( wildcard, '.*' )
        has_wildcard = true
    end

    if code_projection then
        local p = code_projection:apply( s, true )
        if p and #p > 0 then
            s = p
            if not has_wildcard then
                pattern_s = s
            end
        end
    end

    local codes = get_cached_codes( text, db_table, cache )
    if not codes then
        return false
    end

    for _, part in ipairs( codes ) do
        local variants = expand_code_variants( part, code_projection )
        for _, variant in ipairs( variants ) do
            local matched
            if has_wildcard then
                local ok, res = pcall( function()
                    if global_match then
                        return variant:find( pattern_s ) ~= nil
                    else
                        return variant:find( '^' .. pattern_s ) ~= nil
                    end
                end )
                matched = ok and res
            else
                if global_match then
                    matched = variant:find( s, 1, true ) ~= nil
                else
                    matched = variant:sub( 1, #s ) == s
                end
            end
            if matched then
                return true
            end
        end
    end
    return false
end

local function handle_long_cand( if_single_char_first, cand, long_word_cands )
    if if_single_char_first and utf8.len( cand.text ) > 1 then
        table.insert( long_word_cands, cand )
    else
        yield( cand )
    end
end

local f = {}

function f.init( env )
    local config = env.engine.schema.config
    local ns = 'search'
    env.if_schema_lookup = false
    env.if_reverse_lookup = false

    local schema_name = config:get_string( ns .. '/schema' )
    if not env.name_space:find( '^%*' ) then schema_name = env.name_space end
    if not schema_name or schema_name == 'false' or schema_name == '0' or #schema_name == 0 then goto checkdb end
    env.search = Memory( env.engine, Schema( schema_name ) )
    if schema_name and env.search then
        env.if_schema_lookup = true
        env.search_limit = config:get_int( ns .. '/schema_search_limit' ) or 2000
    end

    ::checkdb::

    local db = config:get_list( ns .. '/db' )
    if db and db.size > 0 then
        env.wildcard = alt_lua_punc( config:get_string( ns .. '/wildcard' ) ) or '*'
        env.db_table = {}
        for i = 0, db.size - 1 do table.insert( env.db_table, ReverseLookup( db:get_value_at( i ).value ) ) end
        env.if_reverse_lookup = true
        env._reverse_cache = { _size = 0 }
    end
    if not env.if_reverse_lookup and not env.if_schema_lookup then return end

    local fuma_format = config:get_list( ns .. '/fuma_format' )
    if fuma_format and fuma_format.size > 0 then
        env.code_projection = Projection()
        env.code_projection:load( fuma_format )
    else
        env.code_projection = nil
    end

    env.show_other_cands = config:get_bool( ns .. '/show_other_cands' )
    local search_key = config:get_string( 'key_binder/search' ) or config:get_string( ns .. '/key' ) or '`'
    env.search_key_alt = alt_lua_punc( search_key )
    local code_pattern = config:get_string( ns .. '/code_pattern' ) or '[a-z;]'

    local tag = config:get_list( ns .. '/tags' )
    if tag and tag.size > 0 then
        env.tag = {}
        for i = 0, tag.size - 1 do table.insert( env.tag, tag:get_value_at( i ).value ) end
    else
        env.tag = { 'abc' }
    end

    local rules = config:get_list( ns .. '/input2code_format' )
    if rules and rules.size > 0 then
        env.projection = Projection()
        env.projection:load( rules )
        env.mem = Memory( env.engine, env.engine.schema )
    end

    env.commit_notifier = env.engine.context.commit_notifier:connect(
        function( ctx )
            if env.have_select_commit and env.commit_code then
                local commit_text = ctx:get_commit_text()
                if env.mem then
                    update_dict_entry( commit_text, env.commit_code, env.mem, env.projection )
                end
                ctx.commit_history:push( 'search.lua', commit_text )
                env.have_select_commit = false
            else
                return
            end
        end
    )

    env.notifier = env.engine.context.select_notifier:connect(
        function( ctx )
            local input = ctx.input
            local code = input:match( '^(.-)' .. env.search_key_alt )
            if (not code or #code == 0) then return end

            local preedit = ctx:get_preedit()
            local no_search_string = ctx.input:match( '^(.-)' .. env.search_key_alt )
            local edit = preedit.text:match( '^(.-)' .. env.search_key_alt )
            env.have_select_commit = true

            if edit and edit:match( code_pattern ) then
                ctx.input = no_search_string .. search_key
            else
                ctx.input = no_search_string
                env.commit_code = no_search_string
                ctx:commit()
            end
        end
    )
end

function f.func( input, env )
    local search_key_alt = env.search_key_alt
    local if_reverse = env.if_reverse_lookup
    local if_schema = env.if_schema_lookup
    local code_proj = env.code_projection
    local db_table = env.db_table
    local wildcard = env.wildcard
    local cache = env._reverse_cache

    local code, fuma = env.engine.context.input:match( '^(.-)' .. search_key_alt .. '(.+)$' )
    if (not code or #code == 0) or (not fuma or #fuma == 0) or (not if_reverse and not if_schema) then
        for cand in input:iter() do yield( cand ) end
        return
    end

    local if_single_char_first = env.engine.context:get_option( 'search_single_char' )
    local dict_table
    local fuma_2
    local other_cand = {}
    local long_word_cands = {}

    if if_schema then dict_table = dict_init( fuma, env.search, env.search_limit, code_proj ) end
    if fuma:find( search_key_alt ) then fuma, fuma_2 = fuma:match( '^(.-)' .. search_key_alt .. '(.*)$' ) end

    for cand in input:iter() do
        if cand.type == 'sentence' then
            table.insert( other_cand, cand )
            goto skip
        end

        local cand_text = cand.text
        local text = cand_text
        local text_2 = nil

        local text_len = utf8.len( cand_text ) or 0

        if text_len > 1 then
            text = cand_text:sub( 1, utf8.offset( cand_text, 2 ) - 1 )
            local cand_text_2 = cand_text:gsub( '^' .. text, '' )
            text_2 = cand_text_2:sub( 1, utf8.offset( cand_text_2, 2 ) - 1 )
        end

        if fuma_2 and #fuma_2 > 0 and if_reverse and not if_schema then
            if reverse_lookup( code_proj, db_table, wildcard, text, fuma, false, cache ) and
                ((text_2 and reverse_lookup( code_proj, db_table, wildcard, text_2, fuma_2, false, cache )) or
                    reverse_lookup( code_proj, db_table, wildcard, text, fuma_2, true, cache )) then
                handle_long_cand( if_single_char_first, cand, long_word_cands )
            else
                table.insert( other_cand, cand )
            end
        else
            if (if_reverse and reverse_lookup( code_proj, db_table, wildcard, text, fuma, false, cache )) or
                (if_schema and dict_match( dict_table, text )) then
                handle_long_cand( if_single_char_first, cand, long_word_cands )
            else
                table.insert( other_cand, cand )
            end
        end
        ::skip::
    end

    for _, cand in ipairs( long_word_cands ) do yield( cand ) end
    if env.show_other_cands then for _, cand in ipairs( other_cand ) do yield( cand ) end end
end

function f.tags_match( seg, env )
    for _, v in ipairs( env.tag ) do if seg.tags[v] then return true end end
    return false
end

function f.fini( env )
    if env.if_reverse_lookup or env.if_schema_lookup then
        if env.notifier then env.notifier:disconnect() end
        if env.commit_notifier then env.commit_notifier:disconnect() end
        if env.mem and env.mem.disconnect then env.mem:disconnect() end
        if env.search and env.search.disconnect then env.search:disconnect() end
        env.db_table = nil
        env.mem = nil
        env.search = nil
        env._reverse_cache = nil
        collectgarbage( 'collect' )
    end
end

return f
