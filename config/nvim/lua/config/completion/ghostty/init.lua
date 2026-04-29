local M = {}

local parse = require('config.completion.ghostty.parse')

local keys_cache
local enums_cache
local loading = false

local function loaded()
    return keys_cache ~= nil and enums_cache ~= nil
end

local function parse_output(config_out, enums_content)
    local ok_keys, keys = pcall(parse.parse_keys, config_out)
    if not ok_keys then
        keys = {}
    end

    local ok_enums, enums = pcall(parse.parse_enums, enums_content)
    if not ok_enums then
        enums = {}
    end

    keys_cache = keys
    enums_cache = enums
end

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

local function read_docs()
    if vim.fn.executable('ghostty') == 0 then
        return ''
    end

    local result = vim.system({ 'ghostty', '+show-config', '--docs' }):wait()

    return result.stdout or ''
end

local function read_enums()
    local path = M.bash_completion_path()
    if not path then
        return ''
    end

    local file = io.open(path, 'r')
    if not file then
        return ''
    end

    local content = file:read('*a') or ''
    file:close()
    return content
end

local function load_sync()
    parse_output(read_docs(), read_enums())
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

    local config_out = ''
    local enums_content = ''
    local remaining = 2

    local function done()
        remaining = remaining - 1
        if remaining > 0 then
            return
        end

        loading = false
        parse_output(config_out, enums_content)
    end

    if vim.fn.executable('ghostty') == 1 then
        vim.system({ 'ghostty', '+show-config', '--docs' }, {}, function(result)
            config_out = result.stdout or ''
            done()
        end)
    else
        done()
    end

    enums_content = read_enums()
    done()
end

local function context(base)
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, col)

    if before:match('^%s*#') then
        return
    end

    local eq = before:find('=')
    if eq and col > eq then
        local key = vim.trim(before:sub(1, eq - 1))
        local values = enums_cache and enums_cache[key]
        if not values then
            return
        end

        return {
            base = base,
            kind = 'value',
            start = col - #base,
            values = values,
        }
    end

    if before:match('^%s*[a-z0-9-]*$') then
        local first = before:find('%S') or (col + 1)
        return {
            base = base,
            kind = 'key',
            start = first - 1,
        }
    end
end

local function values(items, base)
    local out = {}
    local query = base:lower()

    for _, value in ipairs(items) do
        if query == '' or value:sub(1, #query):lower() == query then
            out[#out + 1] = {
                abbr = value,
                icase = 1,
                kind = 'v',
                menu = '[ghostty]',
                word = value,
            }
        end
    end

    return out
end

local function keys(base)
    local out = {}
    local query = base:lower()

    for _, item in ipairs(keys_cache or {}) do
        if query == '' or item.word:sub(1, #query):lower() == query then
            out[#out + 1] = item
        end
    end

    return out
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

    if ctx.kind == 'value' then
        return values(ctx.values, base)
    end

    return keys(base)
end

return M
