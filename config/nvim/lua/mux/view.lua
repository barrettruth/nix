---@class mux.ViewEntry
---@field name string
---@field tab integer
---@field current boolean

---@class mux.ViewSpec
---@field restore? boolean
---@field terminal? boolean
---@field internal? boolean
---@field auto? boolean

local M = {}

---@type table<integer, string>
local tab_view = {}

---@type table<string, mux.ViewSpec>
local views = {
    edit = {},
    vcs = { restore = true },
    ai = { restore = true, terminal = true },
    zsh = { restore = true, terminal = true },
    direnv = { terminal = true, internal = true, auto = true },
}

local did_setup = false
local suppress_dirty = false

---@type table<integer, boolean>
local internal_buffers = {}

---@return string
local function root()
    local state = require('mux.server').state()
    return (state.server and state.server.root) or vim.fn.getcwd()
end

---@param name string
---@return nil
local function mark_dirty(name)
    if not suppress_dirty and not views[name].internal then
        require('mux.session').mark_dirty()
    end
end

---@return integer[]
local function user_tabpages()
    return vim.tbl_filter(function(tp)
        local name = tab_view[tp] or 'edit'
        return not views[name].internal
    end, vim.api.nvim_list_tabpages())
end

---@return boolean
local function restore_terminal_focus()
    local name = tab_view[vim.api.nvim_get_current_tabpage()]
    local spec = name and views[name]
    local buf = vim.api.nvim_get_current_buf()
    if
        not spec
        or not spec.terminal
        or vim.bo[buf].buftype ~= 'terminal'
        or not vim.b[buf].term_insert
    then
        return false
    end
    pcall(vim.cmd.startinsert)
    return true
end

---@param name string
---@return integer? tab
local function find(name)
    for tp, view in pairs(tab_view) do
        if view == name and vim.api.nvim_tabpage_is_valid(tp) then
            return tp
        end
    end
end

---@param name string
---@param restoring boolean
---@return nil
local function materialize(name, restoring)
    local cwd = root()
    if name == 'edit' then
        vim.cmd.edit(vim.fn.fnameescape(cwd))
    elseif name == 'vcs' then
        pcall(vim.cmd, 'Git|only')
    elseif name == 'ai' then
        local cmd = restoring and { 'devin', '--continue' } or { 'devin' }
        vim.fn.jobstart(cmd, { term = true, cwd = cwd })
        restore_terminal_focus()
    elseif name == 'zsh' then
        vim.fn.jobstart({ vim.o.shell }, { term = true, cwd = cwd })
        restore_terminal_focus()
    elseif name == 'direnv' then
        vim.fn.jobstart({
            vim.o.shell,
            '-lc',
            'unset TMUX ZELLIJ KITTY_LISTEN_ON; TERM_PROGRAM=; exec direnv-instant start >/dev/null',
        }, { term = true, cwd = cwd })
        restore_terminal_focus()
    end
end

---@param name string
---@param enter boolean
---@return integer win
---@return integer tab
local function create(name, enter)
    local function create_view()
        local buf = vim.api.nvim_create_buf(false, true)
        local tp = vim.api.nvim_open_tabpage(buf, enter, {})
        tab_view[tp] = name
        local win = vim.api.nvim_tabpage_get_win(tp)
        vim.api.nvim_win_call(win, function()
            materialize(name, false)
        end)
        mark_dirty(name)
        return win, tp
    end
    if views[name].internal then
        return require('mux.session').without_dirty(create_view)
    end
    return create_view()
end

---@param name string
---@return integer? win
---@return integer? tab
---@return string? err
function M.ensure(name)
    if not views[name] then
        return nil, nil, 'unknown view: ' .. tostring(name)
    end
    local tp = find(name)
    if tp then
        return vim.api.nvim_tabpage_get_win(tp), tp
    end
    local win, created = create(name, false)
    return win, created
end

---@param name string
---@return true? ok
---@return string? err
function M.open(name)
    local win, tp, err = M.ensure(name)
    if not win then
        return nil, err
    end
    if tp and vim.api.nvim_tabpage_is_valid(tp) then
        vim.api.nvim_set_current_tabpage(tp)
    end
    restore_terminal_focus()
    mark_dirty(name)
    return true
end

---@generic T
---@param name string
---@param fn fun(): T
---@return T? result
---@return string? err
function M.call(name, fn)
    local saved_win = vim.api.nvim_get_current_win()
    local saved_tab = vim.api.nvim_get_current_tabpage()
    local win, _, err = M.ensure(name)
    if not win then
        return nil, err
    end
    local ok, result = pcall(vim.api.nvim_win_call, win, fn)
    if vim.api.nvim_tabpage_is_valid(saved_tab) then
        pcall(vim.api.nvim_set_current_tabpage, saved_tab)
    end
    if vim.api.nvim_win_is_valid(saved_win) then
        pcall(vim.api.nvim_set_current_win, saved_win)
    end
    restore_terminal_focus()
    if not ok then
        return nil, tostring(result)
    end
    mark_dirty(name)
    return result
end

---@return true? ok
---@return string? err
function M.close()
    local tp = vim.api.nvim_get_current_tabpage()
    local name = tab_view[tp] or 'edit'
    if not views[name].internal and #user_tabpages() <= 1 then
        return require('mux.server').close()
    end
    local bufs = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        bufs[#bufs + 1] = vim.api.nvim_win_get_buf(win)
    end
    local ok = pcall(vim.cmd, 'tabclose')
    if not ok then
        return nil, 'failed to close view'
    end
    tab_view[tp] = nil
    for _, buf in ipairs(bufs) do
        if
            vim.api.nvim_buf_is_valid(buf)
            and vim.bo[buf].buftype == 'terminal'
            and #vim.fn.win_findbuf(buf) == 0
        then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
    mark_dirty(name)
    return true
end

---@return nil
function M.initial()
    tab_view[vim.api.nvim_get_current_tabpage()] = 'edit'
    materialize('edit', false)
    require('mux.session').mark_dirty()
end

---@param names string[]?
---@return nil
function M.restore(names)
    tab_view = {}
    for i, tp in ipairs(vim.api.nvim_list_tabpages()) do
        tab_view[tp] = names and names[i] or 'edit'
    end
    local cur = vim.api.nvim_get_current_tabpage()
    for tp, name in pairs(tab_view) do
        if views[name].restore then
            vim.api.nvim_set_current_tabpage(tp)
            materialize(name, true)
        end
    end
    vim.api.nvim_set_current_tabpage(cur)
end

---@return string[]
function M.ordered()
    return vim.tbl_map(function(tp)
        return tab_view[tp] or 'edit'
    end, user_tabpages())
end

---@return boolean
function M.has_internal()
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = tab_view[tp]
        if name and views[name].internal then
            return true
        end
    end
    return false
end

---@return mux.ViewEntry[]
function M.list()
    local cur = vim.api.nvim_get_current_tabpage()
    local out = {}
    for name in pairs(views) do
        local tp = find(name)
        if tp then
            out[#out + 1] = {
                name = name,
                tab = tp,
                current = tp == cur,
            }
        end
    end
    table.sort(out, function(a, b)
        return a.name < b.name
    end)
    return out
end

---@generic T
---@param fn fun(): T
---@return T
function M.without_internal(fn)
    local internal = {}
    local current = vim.api.nvim_get_current_tabpage()
    local current_name = tab_view[current]
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = tab_view[tp]
        if name and views[name].internal then
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
                internal_buffers[vim.api.nvim_win_get_buf(win)] = true
            end
            internal[#internal + 1] = name
        end
    end
    if #internal == 0 then
        return fn()
    end
    local fallback = user_tabpages()[1]
    suppress_dirty = true
    if fallback then
        vim.api.nvim_set_current_tabpage(fallback)
    end
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = tab_view[tp]
        if name and views[name].internal then
            vim.api.nvim_set_current_tabpage(tp)
            pcall(vim.cmd, 'tabclose')
            tab_view[tp] = nil
        end
    end
    if fallback and vim.api.nvim_tabpage_is_valid(fallback) then
        vim.api.nvim_set_current_tabpage(fallback)
    end
    local result = { pcall(fn) }
    for _, name in ipairs(internal) do
        M.ensure(name)
    end
    suppress_dirty = false
    if current_name and views[current_name].internal then
        M.open(current_name)
    elseif vim.api.nvim_tabpage_is_valid(current) then
        vim.api.nvim_set_current_tabpage(current)
    end
    if not result[1] then
        error(result[2])
    end
    return unpack(result, 2)
end

---@return nil
function M.start_auto()
    if
        vim.fn.executable('direnv-instant') == 1
        and vim.uv.fs_stat(root() .. '/.envrc')
    then
        M.ensure('direnv')
    end
end

---@param buf integer
---@return nil
local function cleanup_terminal(buf)
    local dirty = not internal_buffers[buf]
    internal_buffers[buf] = nil
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_is_valid(win) then
            local tp = vim.api.nvim_win_get_tabpage(win)
            local name = tab_view[tp]
            local spec = name and views[name]
            if spec and spec.terminal then
                dirty = dirty and not spec.internal
                if not spec.internal and #user_tabpages() <= 1 then
                    require('mux.server').close()
                    return
                end
                local function close_tab()
                    pcall(vim.api.nvim_set_current_tabpage, tp)
                    if spec.internal and #vim.api.nvim_list_tabpages() <= 1 then
                        tab_view[tp] = 'edit'
                        materialize('edit', false)
                        return false
                    end
                    local ok = pcall(vim.cmd, 'tabclose')
                    if ok then
                        tab_view[tp] = nil
                    end
                    return ok
                end
                if spec.internal then
                    require('mux.session').without_dirty(close_tab)
                else
                    close_tab()
                end
            end
        end
    end
    local function delete_buf()
        if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
    if dirty then
        delete_buf()
        require('mux.session').mark_dirty()
    else
        require('mux.session').without_dirty(delete_buf)
    end
end

---@return nil
local function setup_keymaps()
    local modes = { 'n', 'i', 't' }
    local prefix = '<a-x>'
    for mode, rhs in pairs({
        n = '<c-w>',
        i = '<c-o><c-w>',
        t = '<c-\\><c-n><c-w>',
    }) do
        vim.keymap.set(mode, prefix, rhs, {
            remap = true,
            desc = 'mux: window command prefix',
        })
    end
    local function map(lhs, rhs, desc)
        vim.keymap.set(modes, lhs, rhs, { desc = desc, silent = true })
    end
    for _, entry in ipairs({
        { key = 'e', name = 'edit' },
        { key = 'v', name = 'vcs' },
        { key = 'a', name = 'ai' },
        { key = 'z', name = 'zsh' },
    }) do
        map(prefix .. entry.key, function()
            M.open(entry.name)
        end, 'mux: ' .. entry.name .. ' view')
    end
    map(prefix .. 'x', function()
        M.close()
    end, 'mux: close view')
    map(prefix .. 'X', function()
        require('mux.server').kill()
    end, 'mux: kill session')
    map(prefix .. 'B', function()
        require('mux.line').toggle()
    end, 'mux: toggle bar')
    map(prefix .. '[', function()
        require('mux.line').cycle(-1)
    end, 'mux: previous server')
    map(prefix .. ']', function()
        require('mux.line').cycle(1)
    end, 'mux: next server')
    map(prefix .. 'r', function()
        require('mux.server').reload()
    end, 'mux: reload')
end

---@return nil
function M.setup()
    if did_setup then
        return
    end
    did_setup = true
    setup_keymaps()
    local group = vim.api.nvim_create_augroup('mux-view', { clear = true })
    vim.api.nvim_create_autocmd('TermClose', {
        group = group,
        callback = function(args)
            if vim.api.nvim_buf_is_valid(args.buf) then
                vim.schedule(function()
                    cleanup_terminal(args.buf)
                end)
            end
        end,
    })
end

return M
