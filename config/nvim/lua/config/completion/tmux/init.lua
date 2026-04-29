---@type config.completion.Provider
local M = {
    source = 'tmux',
}

local loader = require('config.completion.loader')
local parse = require('config.completion.tmux.parse')
local util = require('config.completion.util')

---@type config.completion.Items?
local cache

local MAN_COMMAND = {
    'bash',
    '-c',
    'MANWIDTH=80 man -P cat tmux 2>/dev/null',
}

local NAMES_COMMAND = {
    'tmux',
    'list-commands',
    '-F',
    '#{command_list_name}',
}

local COMMANDS_COMMAND = { 'tmux', 'list-commands' }

local function loaded()
    return cache ~= nil
end

---@param man_out string
---@param names_out string
---@param commands_out string
local function parse_output(man_out, names_out, commands_out)
    local descriptions =
        util.safe_call(parse.parse_descriptions, {}, man_out, names_out)
    cache = util.safe_call(parse.parse, {}, commands_out, descriptions)
end

local source_loader = loader.new({
    loaded = loaded,
    store = function(outputs)
        parse_output(outputs[1], outputs[2], outputs[3])
    end,
    tasks = {
        util.system_task('bash', MAN_COMMAND),
        util.system_task('tmux', NAMES_COMMAND),
        util.system_task('tmux', COMMANDS_COMMAND),
    },
})

M.preload = source_loader.preload

---@class config.completion.tmux.Context
---@field base string
---@field start integer

---@param base string
---@return config.completion.tmux.Context?
local function context(base)
    local line_ctx = util.context(base)
    local before = line_ctx.before

    if before:match('^%s*#') then
        return
    end

    if not before:match('^%s*[a-z-]*$') then
        return
    end

    local first = before:find('%S') or (line_ctx.col + 1)
    local command_base = before:match('^%s*([a-z-]*)$') or base

    return {
        base = command_base,
        start = first - 1,
    }
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

    return util.filter_items(cache or {}, ctx.base)
end

return M
