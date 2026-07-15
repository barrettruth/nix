---@class mux.ViewEntry
---@field kind 'view'|'task'|'tab'
---@field name? string
---@field persist? string|false Persisted tab identity; `false` preserves ordinary Vim tabs.
---@field label string
---@field tab integer
---@field current boolean

---@class mux.ViewSpec
---@field restore? boolean
---@field terminal? boolean

local M = {}

---@type table<integer, string|false>
local tab_view = {}

---@type table<string, mux.ViewSpec>
local views = {
    edit = {},
    vcs = { restore = true },
    ai = { restore = true, terminal = true },
    zsh = { restore = true, terminal = true },
}

---@class mux.Task
---@field tab? integer
---@field buf? integer
---@field release? fun()

---@type table<string, mux.Task>
local tasks = {
    direnv = {},
}

local did_setup = false

---@return string
local function root()
    local state = require('mux.server').state()
    return (state.server and state.server.root) or vim.fn.getcwd()
end

---@param tp integer
---@return string? name
---@return mux.Task? task
local function task_for_tab(tp)
    for name, task in pairs(tasks) do
        if task.tab == tp and vim.api.nvim_tabpage_is_valid(tp) then
            return name, task
        end
    end
end

---@param buf integer
---@return string? name
---@return mux.Task? task
local function task_for_buf(buf)
    for name, task in pairs(tasks) do
        if task.buf == buf then
            return name, task
        end
    end
end

---@param name string|false|nil
---@return nil
local function mark_dirty(name)
    if name == false or (type(name) == 'string' and views[name]) then
        require('mux.session').mark_dirty()
    end
end

---@return integer[]
local function user_tabpages()
    return vim.tbl_filter(function(tp)
        return task_for_tab(tp) == nil
    end, vim.api.nvim_list_tabpages())
end

---@return boolean
local function restore_terminal_focus()
    local tp = vim.api.nvim_get_current_tabpage()
    local name = tab_view[tp]
    local spec = name and views[name]
    local buf = vim.api.nvim_get_current_buf()
    if
        not ((spec and spec.terminal) or task_for_tab(tp))
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
    end
end

---@param name string
---@param enter boolean
---@return integer win
---@return integer tab
local function create(name, enter)
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

---Create a user view tab if it does not already exist.
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

---Run a callback inside a user view, then restore focus.
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

---Close the current user view or transient task.
---@return true? ok
---@return string? err
function M.close()
    local tp = vim.api.nvim_get_current_tabpage()
    local _, task = task_for_tab(tp)
    if task then
        if task.buf and vim.api.nvim_buf_is_valid(task.buf) then
            pcall(vim.api.nvim_buf_delete, task.buf, { force = true })
        end
        return true
    end
    local name = tab_view[tp]
    if name == nil then
        name = false
    end
    if #user_tabpages() <= 1 then
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

---@param name string
---@return nil
local function release_task(name)
    local task = tasks[name]
    local release = task.release
    task.tab = nil
    task.buf = nil
    task.release = nil
    if release then
        release()
    end
end

---@return nil
local function start_direnv()
    local task = tasks.direnv
    if task.tab and vim.api.nvim_tabpage_is_valid(task.tab) then
        return
    end
    local cwd = root()
    if
        vim.fn.executable('direnv-instant') == 0
        or not vim.uv.fs_stat(cwd .. '/.envrc')
    then
        return
    end
    local release = require('mux.session').hold()
    local buf = vim.api.nvim_create_buf(false, true)
    local tp = vim.api.nvim_open_tabpage(buf, false, {})
    task.tab = tp
    task.release = release
    local win = vim.api.nvim_tabpage_get_win(tp)
    local ok, job = pcall(vim.api.nvim_win_call, win, function()
        local id = vim.fn.jobstart({
            vim.o.shell,
            '-lc',
            'unset TMUX ZELLIJ KITTY_LISTEN_ON; TERM_PROGRAM=; exec direnv-instant start >/dev/null',
        }, { term = true, cwd = cwd })
        task.buf = vim.api.nvim_get_current_buf()
        restore_terminal_focus()
        return id
    end)
    if ok and type(job) == 'number' and job > 0 then
        return
    end
    if vim.api.nvim_tabpage_is_valid(tp) then
        pcall(vim.api.nvim_set_current_tabpage, tp)
        pcall(vim.cmd, 'tabclose')
    end
    release_task('direnv')
end

---Restore saved labels or bootstrap the default edit view.
---`nil` means no saved session; `false` means ordinary Vim tab.
---@param names (string|false)[]?
---@return nil
function M.restore(names)
    tab_view = {}
    if not names then
        local tp = vim.api.nvim_get_current_tabpage()
        tab_view[tp] = 'edit'
        materialize('edit', false)
        require('mux.session').mark_dirty()
        start_direnv()
        return
    end
    for i, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = names[i]
        tab_view[tp] = type(name) == 'string' and views[name] and name or false
    end
    local cur = vim.api.nvim_get_current_tabpage()
    for tp, name in pairs(tab_view) do
        if type(name) == 'string' and views[name].restore then
            vim.api.nvim_set_current_tabpage(tp)
            materialize(name, true)
        end
    end
    vim.api.nvim_set_current_tabpage(cur)
    start_direnv()
end

---@param buf integer
---@return string
local function default_buf_label(buf)
    local name = vim.fn.bufname(buf)
    if name == '' then
        return '[No Name]'
    end
    if vim.bo[buf].buftype == 'help' then
        return vim.fn.fnamemodify(name, ':t')
    end
    if vim.bo[buf].buftype ~= '' then
        return name
    end
    return vim.fn.pathshorten(vim.fn.fnamemodify(name, ':~'), 1)
end

-- Match Nvim's default tabline: tab current window, window count, modified mark, shortened name.
---@param tp integer
---@return string
local function default_tab_label(tp)
    local win = vim.api.nvim_tabpage_get_win(tp)
    local buf = vim.api.nvim_win_get_buf(win)
    local label = default_buf_label(buf)
    local count = 0
    local modified = false
    for _, other in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        local config = vim.api.nvim_win_get_config(other)
        if config.relative == '' and config.focusable ~= false then
            count = count + 1
            if vim.bo[vim.api.nvim_win_get_buf(other)].modified then
                modified = true
            end
        end
    end
    local prefix = count > 1 and tostring(count) or ''
    prefix = modified and (prefix .. '+') or prefix
    return prefix ~= '' and (prefix .. ' ' .. label) or label
end

---List visible mux entries and ordinary tabs.
---@return mux.ViewEntry[]
function M.list()
    local cur = vim.api.nvim_get_current_tabpage()
    local out = {}
    local labels = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local task_name = task_for_tab(tp)
        local view_name = tab_view[tp]
        local entry
        if task_name then
            entry = {
                kind = 'task',
                name = task_name,
                label = task_name,
                tab = tp,
                current = tp == cur,
            }
        elseif type(view_name) == 'string' and views[view_name] then
            entry = {
                kind = 'view',
                name = view_name,
                persist = view_name,
                label = view_name,
                tab = tp,
                current = tp == cur,
            }
        else
            entry = {
                kind = 'tab',
                persist = false,
                label = default_tab_label(tp),
                tab = tp,
                current = tp == cur,
            }
        end
        out[#out + 1] = entry
        labels[entry.label] = (labels[entry.label] or 0) + 1
    end
    for _, entry in ipairs(out) do
        if entry.persist == false and labels[entry.label] > 1 then
            entry.label = vim.api.nvim_tabpage_get_number(entry.tab)
                .. ':'
                .. entry.label
        end
    end
    return out
end

---@param buf integer
---@return nil
local function cleanup_task(buf)
    local name, task = task_for_buf(buf)
    if not name or not task then
        return
    end
    local tp = task.tab
    if tp and vim.api.nvim_tabpage_is_valid(tp) then
        pcall(vim.api.nvim_set_current_tabpage, tp)
        if #vim.api.nvim_list_tabpages() <= 1 then
            tab_view[tp] = 'edit'
            materialize('edit', false)
        else
            pcall(vim.cmd, 'tabclose')
        end
    end
    if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    release_task(name)
end

---@param buf integer
---@return nil
local function cleanup_terminal(buf)
    if task_for_buf(buf) then
        cleanup_task(buf)
        return
    end
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_is_valid(win) then
            local tp = vim.api.nvim_win_get_tabpage(win)
            local name = tab_view[tp]
            local spec = name and views[name]
            if spec and spec.terminal then
                if #user_tabpages() <= 1 then
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
    map(prefix .. 'r', function()
        require('mux.server').reload()
    end, 'mux: reload')
end

---Install view keymaps and terminal lifecycle cleanup.
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
