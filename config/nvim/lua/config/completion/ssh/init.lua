local M = {}

local parse = require('config.completion.ssh.parse')

local keywords_cache
local enums_cache
local loading = false

local function loaded()
    return keywords_cache ~= nil and enums_cache ~= nil
end

local function parse_outputs(man_out, enums_out)
    local ok_keywords, keywords = pcall(parse.parse_keywords, man_out)
    if not ok_keywords then
        keywords = {}
    end

    local ok_man_enums, man_enums = pcall(parse.extract_enums_from_man, man_out)
    if not ok_man_enums then
        man_enums = {}
    end

    local ok_enums, enums = pcall(parse.parse_enums, enums_out, man_enums)
    if not ok_enums then
        enums = {}
    end

    keywords_cache = keywords
    enums_cache = enums
end

local function read_man()
    if vim.fn.executable('man') == 0 then
        return ''
    end

    local result = vim.system({
        'bash',
        '-c',
        'MANWIDTH=80 man -P cat ssh_config 2>/dev/null',
    }):wait()

    return result.stdout or ''
end

local function read_enums()
    if vim.fn.executable('ssh') == 0 then
        return ''
    end

    local result = vim.system({
        'bash',
        '-c',
        'for q in cipher cipher-auth mac kex key key-cert key-plain key-sig protocol-version compression sig; do echo "##$q"; ssh -Q "$q" 2>/dev/null; done',
    }):wait()

    return result.stdout or ''
end

local function load_sync()
    parse_outputs(read_man(), read_enums())
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
    local enums_out = ''
    local remaining = 2

    local function done()
        remaining = remaining - 1
        if remaining > 0 then
            return
        end

        loading = false
        parse_outputs(man_out, enums_out)
    end

    if vim.fn.executable('man') == 1 then
        vim.system(
            { 'bash', '-c', 'MANWIDTH=80 man -P cat ssh_config 2>/dev/null' },
            {},
            function(result)
                man_out = result.stdout or ''
                done()
            end
        )
    else
        done()
    end

    if vim.fn.executable('ssh') == 1 then
        vim.system({
            'bash',
            '-c',
            'for q in cipher cipher-auth mac kex key key-cert key-plain key-sig protocol-version compression sig; do echo "##$q"; ssh -Q "$q" 2>/dev/null; done',
        }, {}, function(result)
            enums_out = result.stdout or ''
            done()
        end)
    else
        done()
    end
end

local function context()
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, col)

    if before:match('^%s*#') then
        return
    end

    if before:match('^%s*%S*$') then
        local first = before:find('%S') or (col + 1)
        return {
            kind = 'keyword',
            keyword = before:match('^%s*(%S*)$') or '',
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

    local base = rest:match('([^,%s]*)$') or ''
    return {
        base = base,
        enums = enums,
        keyword = keyword,
        kind = 'value',
        start = col - #base,
    }
end

local function enum_items(values)
    local items = {}
    for _, value in ipairs(values) do
        items[#items + 1] = {
            abbr = value,
            icase = 1,
            kind = 'v',
            menu = '[ssh]',
            word = value,
        }
    end
    return items
end

function M.complete(findstart, _)
    ensure_loaded()

    local ctx = context()
    if findstart == 1 then
        return ctx and ctx.start or -2
    end

    if not ctx then
        return {}
    end

    if ctx.kind == 'keyword' then
        return keywords_cache or {}
    end

    return enum_items(ctx.enums)
end

return M
