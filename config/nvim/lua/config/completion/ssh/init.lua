---@type config.completion.Provider
local M = {
    source = 'ssh',
}

local loader = require('config.completion.loader')
local parse = require('config.completion.ssh.parse')
local util = require('config.completion.util')

---@type config.completion.Items?
local keywords_cache

---@type table<string, string[]>?
local enums_cache

local MAN_COMMAND = {
    'bash',
    '-c',
    'MANWIDTH=80 man -P cat ssh_config 2>/dev/null',
}

local ENUM_COMMAND = {
    'bash',
    '-c',
    'for q in cipher cipher-auth mac kex key key-cert key-plain key-sig protocol-version compression sig; do echo "##$q"; ssh -Q "$q" 2>/dev/null; done',
}

local function loaded()
    return keywords_cache ~= nil and enums_cache ~= nil
end

---@param man_out string
---@param enums_out string
local function parse_outputs(man_out, enums_out)
    local keywords = util.safe_call(parse.parse_keywords, {}, man_out)
    local man_enums = util.safe_call(parse.extract_enums_from_man, {}, man_out)
    local enums = util.safe_call(parse.parse_enums, {}, enums_out, man_enums)

    keywords_cache = keywords
    enums_cache = enums
end

local source_loader = loader.new({
    loaded = loaded,
    store = function(outputs)
        parse_outputs(outputs[1], outputs[2])
    end,
    tasks = {
        util.system_task('bash', MAN_COMMAND),
        util.system_task('bash', ENUM_COMMAND),
    },
})

M.preload = source_loader.preload

---@class config.completion.ssh.Context
---@field base string
---@field enums? string[]
---@field kind 'keyword'|'value'
---@field start integer

---@param base string
---@return config.completion.ssh.Context?
local function context(base)
    local line_ctx = util.context(base)
    local before = line_ctx.before

    if before:match('^%s*#') then
        return
    end

    if before:match('^%s*%S*$') then
        local first = before:find('%S') or (line_ctx.col + 1)
        local keyword_base = before:match('^%s*(%S*)$') or base

        return {
            base = keyword_base,
            kind = 'keyword',
            start = first - 1,
        }
    end

    local keyword, rest = before:match('^%s*(%S+)%s+(.-)$')
    if not keyword then
        return
    end

    local enums = enums_cache and enums_cache[keyword:lower()]
    if not enums then
        return
    end

    local value_base = rest:match('([^,%s]*)$') or base

    return {
        base = value_base,
        enums = enums,
        kind = 'value',
        start = line_ctx.col - #value_base,
    }
end

---@param values string[]
---@param base string
---@return config.completion.Items
local function enum_items(values, base)
    local items = {}

    for _, value in ipairs(util.filter_strings(values, base, true)) do
        items[#items + 1] = {
            abbr = value,
            icase = 1,
            kind = 'ssh',
            user_data = {
                source = M.source,
            },
            word = value,
        }
    end

    return items
end

---@param base string
---@return config.completion.Items
local function keyword_items(base)
    return util.filter_items(keywords_cache or {}, base)
end

---@param findstart integer
---@param base string
---@return integer|config.completion.Items
function M.complete(findstart, base)
    source_loader.ensure_loaded()

    local ctx = context(base)
    if findstart == 1 then
        return ctx and ctx.start or -2
    end

    if not ctx then
        return {}
    end

    if ctx.kind == 'keyword' then
        return keyword_items(ctx.base)
    end

    return enum_items(ctx.enums or {}, ctx.base)
end

return M
