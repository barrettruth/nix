local M = {}

local function state(ctx)
    if ctx.filetype ~= 'lua' then
        return
    end

    local ok_buf, Buf = pcall(require, 'lazydev.buf')
    local ok_config, Config = pcall(require, 'lazydev.config')
    local ok_pkg, Pkg = pcall(require, 'lazydev.pkg')
    if not (ok_buf and ok_config and ok_pkg) then
        return
    end

    if not Buf.attached[ctx.bufnr] then
        return
    end

    local req, forward_slash = Pkg.get_module(ctx.before, { before = true })
    if req == nil then
        return
    end

    return {
        Config = Config,
        Pkg = Pkg,
        forward_slash = forward_slash and true or false,
        prefix = forward_slash and req:gsub('%.', '/') or req,
        req = req,
    }
end

local function module_start(ctx)
    local start = ctx.col
    while start > 0 and ctx.before:sub(start, start):match('[%w%.%-_/]') do
        start = start - 1
    end
    return start
end

local function add(items, st, modname, modpath)
    local word = st.forward_slash and modname:gsub('%.', '/') or modname
    if st.prefix ~= '' and word:sub(1, #st.prefix) ~= st.prefix then
        return
    end

    local plugin = st.Pkg.get_plugin_name(modpath)
    items[modname] = items[modname]
        or {
            word = word,
            abbr = word,
            info = plugin and ('Plugin: ' .. plugin) or nil,
            kind = 'm',
            menu = '[lazydev]',
            user_data = {
                source = 'lazydev',
            },
        }
end

function M.findstart(ctx)
    local st = state(ctx)
    if not st then
        return
    end

    return module_start(ctx)
end

function M.complete(ctx)
    local st = state(ctx)
    if not st then
        return {}
    end

    local items = {}
    if not st.req:find('.', 1, true) then
        st.Pkg.topmods(function(modname, modpath)
            add(items, st, modname, modpath)
        end)
        for _, lib in ipairs(st.Config.libs) do
            for _, mod in ipairs(lib.mods) do
                add(items, st, mod, lib.path)
            end
        end
    else
        st.Pkg.lsmod(st.req:gsub('%.[^%.]*$', ''), function(modname, modpath)
            add(items, st, modname, modpath)
        end)
    end

    local words = vim.tbl_values(items)
    table.sort(words, function(a, b)
        return a.word < b.word
    end)
    return words
end

function M.convert_lsp_item(_, ctx)
    if not state(ctx) then
        return
    end

    return {
        dup = 0,
    }
end

return M
