---@type config.completion.Provider
local M = {
    source = 'ghostty',
}

local loader = require('config.completion.loader')
local parse = require('config.completion.ghostty.parse')
local util = require('config.completion.util')

---@type config.completion.Items?
local keys_cache

---@type table<string, string[]>?
local enums_cache

local DOC_COMMAND = {
    'ghostty',
    '+show-config',
    '--default',
    '--docs',
}

local function loaded()
    return keys_cache ~= nil and enums_cache ~= nil
end

---@param config_out string
---@param enums_content string
local function parse_output(config_out, enums_content)
    keys_cache = util.safe_call(parse.parse_keys, {}, config_out)
    enums_cache = util.safe_call(parse.parse_enums, {}, enums_content)
end

---@return string?
function M.bash_completion_path()
    local bin = vim.fn.exepath('ghostty')
    if bin == '' then
        return
    end

    local real = vim.uv.fs_realpath(bin)
    if not real then
        return
    end

    local prefix = real:match('(.*)/bin/ghostty$')
    if not prefix then
        return
    end

    return prefix .. '/share/bash-completion/completions/ghostty.bash'
end

local source_loader = loader.new({
    loaded = loaded,
    store = function(outputs)
        parse_output(outputs[1], outputs[2])
    end,
    tasks = {
        util.system_task('ghostty', DOC_COMMAND),
        util.file_task(M.bash_completion_path),
    },
})

M.preload = source_loader.preload

---@class config.completion.ghostty.Context
---@field base string
---@field kind 'key'|'value'
---@field start integer
---@field values? string[]

---@param base string
---@return config.completion.ghostty.Context?
local function context(base)
    local line_ctx = util.context(base)
    local before = line_ctx.before

    if before:match('^%s*#') then
        return
    end

    local eq = before:match('.*()=')
    if eq and line_ctx.col > eq then
        local key = vim.trim(before:sub(1, eq - 1))
        local values = enums_cache and enums_cache[key]
        if not values then
            return
        end

        local value_base = before:sub(eq + 1):match('([^%s]*)$') or base

        return {
            base = value_base,
            kind = 'value',
            start = line_ctx.col - #value_base,
            values = values,
        }
    end

    if before:match('^%s*[a-z0-9-]*$') then
        local first = before:find('%S') or (line_ctx.col + 1)
        local key_base = before:match('^%s*([a-z0-9-]*)$') or base

        return {
            base = key_base,
            kind = 'key',
            start = first - 1,
        }
    end
end

---@param values string[]
---@param base string
---@return config.completion.Items
local function value_items(values, base)
    local items = {}

    for _, value in ipairs(util.filter_strings(values, base, true)) do
        items[#items + 1] = {
            abbr = value,
            icase = 1,
            kind = 'v',
            menu = '[ghostty]',
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
local function key_items(base)
    return util.filter_items(keys_cache or {}, base)
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

    if ctx.kind == 'value' then
        return value_items(ctx.values or {}, ctx.base)
    end

    return key_items(ctx.base)
end

return M
