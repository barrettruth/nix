local M = {}

local parse = require('config.completion.tmux.parse')

local cache
local loading = false

local function loaded()
    return cache ~= nil
end

local function parse_output(man_out, names_out, commands_out)
    local ok_desc, descriptions =
        pcall(parse.parse_descriptions, man_out, names_out)
    if not ok_desc then
        descriptions = {}
    end

    local ok_items, items = pcall(parse.parse, commands_out, descriptions)
    cache = ok_items and items or {}
end

local function read_man()
    if vim.fn.executable('man') == 0 then
        return ''
    end

    local result = vim.system({
        'bash',
        '-c',
        'MANWIDTH=80 man -P cat tmux 2>/dev/null',
    }):wait()

    return result.stdout or ''
end

local function read_names()
    if vim.fn.executable('tmux') == 0 then
        return ''
    end

    local result = vim.system({
        'tmux',
        'list-commands',
        '-F',
        '#{command_list_name}',
    }):wait()

    return result.stdout or ''
end

local function read_commands()
    if vim.fn.executable('tmux') == 0 then
        return ''
    end

    local result = vim.system({ 'tmux', 'list-commands' }):wait()

    return result.stdout or ''
end

local function load_sync()
    parse_output(read_man(), read_names(), read_commands())
end

local function ensure_loaded()
    if loaded() then
        return
    end

    if loading then
        vim.wait(2000, loaded, 20)
    end

    if not loaded() then
        load_sync()
    end
end

function M.preload()
    if loaded() or loading then
        return
    end

    loading = true

    local man_out = ''
    local names_out = ''
    local commands_out = ''
    local remaining = 3

    local function done()
        remaining = remaining - 1
        if remaining > 0 then
            return
        end

        loading = false
        parse_output(man_out, names_out, commands_out)
    end

    if vim.fn.executable('man') == 1 then
        vim.system(
            { 'bash', '-c', 'MANWIDTH=80 man -P cat tmux 2>/dev/null' },
            {},
            function(result)
                man_out = result.stdout or ''
                done()
            end
        )
    else
        done()
    end

    if vim.fn.executable('tmux') == 1 then
        vim.system({
            'tmux',
            'list-commands',
            '-F',
            '#{command_list_name}',
        }, {}, function(result)
            names_out = result.stdout or ''
            done()
        end)
        vim.system({ 'tmux', 'list-commands' }, {}, function(result)
            commands_out = result.stdout or ''
            done()
        end)
    else
        done()
        done()
    end
end

local function context(base)
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, col)

    if before:match('^%s*#') then
        return
    end

    if not before:match('^%s*[a-z-]*$') then
        return
    end

    local first = before:find('%S') or (col + 1)
    return {
        base = base,
        start = first - 1,
    }
end

function M.complete(findstart, base)
    ensure_loaded()

    local ctx = context(base)
    if findstart == 1 then
        return ctx and ctx.start or -2
    end

    if not ctx then
        return {}
    end

    local query = base:lower()
    local items = {}
    for _, item in ipairs(cache or {}) do
        if query == '' or item.word:sub(1, #query):lower() == query then
            items[#items + 1] = item
        end
    end

    return items
end

return M
