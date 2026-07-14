---@class mux.ViewEntry
---@field name string
---@field tab integer
---@field current boolean

---@class mux.ViewSpec
---@field restore? boolean
---@field terminal? boolean

local M = {}

---@type table<integer, string>
local tab_view = {}

---@type table<string, mux.ViewSpec>
local views = {
    edit = {},
    vcs = { restore = true },
    ai = { restore = true, terminal = true },
    zsh = { restore = true, terminal = true },
}

local did_setup = false

local function root()
    local server = require('mux.server')._record()
    return (server and server.root) or vim.fn.getcwd()
end

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

local function find(name)
    for tp, view in pairs(tab_view) do
        if view == name and vim.api.nvim_tabpage_is_valid(tp) then
            return tp
        end
    end
end

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
    end
end

local function create(name, enter)
    local buf = vim.api.nvim_create_buf(false, true)
    local tp = vim.api.nvim_open_tabpage(buf, enter, {})
    tab_view[tp] = name
    local win = vim.api.nvim_tabpage_get_win(tp)
    vim.api.nvim_win_call(win, function()
        materialize(name, false)
    end)
    require('mux.session').mark_dirty()
    return win, tp
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
    require('mux.session').mark_dirty()
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
    require('mux.session').mark_dirty()
    return result
end

---@return true? ok
---@return string? err
function M.close()
    local tp = vim.api.nvim_get_current_tabpage()
    if #vim.api.nvim_list_tabpages() <= 1 then
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
    require('mux.session').mark_dirty()
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
    local tabs = vim.api.nvim_list_tabpages()
    for i, name in ipairs(names or {}) do
        if tabs[i] and vim.api.nvim_tabpage_is_valid(tabs[i]) then
            tab_view[tabs[i]] = name
        end
    end
    local cur = vim.api.nvim_get_current_tabpage()
    for tp, name in pairs(tab_view) do
        local spec = views[name]
        if spec and spec.restore and vim.api.nvim_tabpage_is_valid(tp) then
            vim.api.nvim_set_current_tabpage(tp)
            materialize(name, true)
        end
    end
    if vim.api.nvim_tabpage_is_valid(cur) then
        pcall(vim.api.nvim_set_current_tabpage, cur)
    end
end

---@return string[]
function M.ordered()
    local out = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        out[#out + 1] = tab_view[tp] or 'edit'
    end
    return out
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

local function cleanup_terminal(buf)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_is_valid(win) then
            local tp = vim.api.nvim_win_get_tabpage(win)
            local name = tab_view[tp]
            local spec = name and views[name]
            if spec and spec.terminal then
                if #vim.api.nvim_list_tabpages() <= 1 then
                    require('mux.server').close()
                    return
                end
                pcall(vim.api.nvim_set_current_tabpage, tp)
                pcall(vim.cmd, 'tabclose')
                tab_view[tp] = nil
            end
        end
    end
    if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    require('mux.session').mark_dirty()
end

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
    map(prefix .. 'e', function()
        M.open('edit')
    end, 'mux: edit view')
    map(prefix .. 'v', function()
        M.open('vcs')
    end, 'mux: vcs view')
    map(prefix .. 'a', function()
        M.open('ai')
    end, 'mux: ai view')
    map(prefix .. 'z', function()
        M.open('zsh')
    end, 'mux: zsh view')
    map(prefix .. 'x', function()
        M.close()
    end, 'mux: close view')
    map(prefix .. 'B', function()
        require('mux.line').toggle()
    end, 'mux: toggle bar')
    map(prefix .. '[', function()
        require('mux.line').cycle(-1)
    end, 'mux: previous server')
    map(prefix .. ']', function()
        require('mux.line').cycle(1)
    end, 'mux: next server')
    map(prefix .. 'd', function()
        require('mux.server').detach()
    end, 'mux: detach')
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
