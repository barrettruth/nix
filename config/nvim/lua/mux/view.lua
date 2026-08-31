---@class mux.ViewEntry
---@field kind 'view'|'tab'
---@field name? string
---@field persist? string|false Persisted tab identity; `false` preserves ordinary Vim tabs.
---@field label string
---@field tab integer
---@field current boolean

---@class mux.ViewSpec
---@field restore? boolean
---@field terminal? boolean

local M = {}

local JOB_EXIT_TIMEOUT_MS = 5000
local MODES = { 'n', 'i', 't' }
local PREFIX = '<a-x>'

---@type table<integer, string|false>
local tab_view = {}

---Pty group leaders for live mux terminals, keyed by buffer.
---@type table<integer, integer>
local term_pids = {}

---@type table<string, mux.ViewSpec>
local views = {
    edit = {},
    vcs = { restore = true },
    zsh = { restore = true, terminal = true },
}

local did_setup = false

---@return string
local function root()
    local state = require('mux.server').state()

    return (state.server and state.server.root) or vim.fn.getcwd()
end

---@param name string|false|nil
---@return nil
local function mark_dirty(name)
    if name == false or (name and views[name]) then
        require('mux.session').mark_dirty()
    end
end

---@return integer[]
local function user_tabpages()
    return vim.api.nvim_list_tabpages()
end

---@return mux.State? state
---@return string? err
local function delete_session()
    local server = require('mux.server')
    local state = server.state()
    local ok, err = require('mux.session').delete()

    if not ok then
        return nil, err
    end

    if state.server then
        vim.fn.serverstop(state.server.socket)
    end

    return state
end

function M.stop()
    local state, err = delete_session()
    if not state then
        return nil, err
    end

    vim.schedule(function()
        vim.cmd.qall({ bang = true })
    end)

    return true
end

function M.retire()
    local server = require('mux.server')
    local state = server.state()
    local targets = {}

    for _, entry in ipairs(server.ordered()) do
        if state.server and entry.root ~= state.server.root then
            if entry.root == state.last_root then
                table.insert(targets, 1, entry)
            else
                targets[#targets + 1] = entry
            end
        end
    end

    local deleted, err = delete_session()
    if not deleted then
        return nil, err
    end

    if #vim.api.nvim_list_uis() == 0 then
        vim.schedule(function()
            vim.cmd.qall({ bang = true })
        end)
        return true
    end

    local function exit(detach)
        if detach and #vim.api.nvim_list_uis() > 0 then
            vim.cmd.detach()
        end

        vim.cmd.qall({ bang = true })
    end

    local function handoff(index)
        local target = targets[index]

        if not target then
            exit(true)
            return
        end

        server.switch(target, function(connected)
            if connected then
                exit(false)
            else
                handoff(index + 1)
            end
        end, true)
    end

    handoff(1)

    return true
end

---@return boolean
local function restore_terminal_focus()
    local tp = vim.api.nvim_get_current_tabpage()
    local name = tab_view[tp]
    local spec = name and views[name]
    local buf = vim.api.nvim_get_current_buf()
    if
        not (spec and spec.terminal)
        or vim.bo[buf].buftype ~= 'terminal'
        or vim.w.term_mode == 'nt'
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
---@return nil
local function materialize(name)
    local cwd = root()

    if name == 'edit' then
        vim.cmd.edit(vim.fn.fnameescape(cwd))
    elseif name == 'vcs' then
        pcall(function()
            vim.cmd.Git()
            vim.cmd.only()
        end)
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
    vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tp), function()
        materialize(name)
    end)
    mark_dirty(name)

    return vim.api.nvim_tabpage_get_win(tp), tp
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

---Switch to an existing tab, whether or not it holds a user view.
---@param tab integer
---@return true? ok
---@return string? err
function M.focus(tab)
    if not vim.api.nvim_tabpage_is_valid(tab) then
        return nil, 'unknown tab'
    end

    vim.api.nvim_set_current_tabpage(tab)
    restore_terminal_focus()
    mark_dirty(tab_view[tab] or false)

    return true
end

---@param step integer
---@return true? ok
---@return string? err
local function walk(step)
    local tabs = user_tabpages()
    local cur = vim.api.nvim_get_current_tabpage()
    local from = 0

    for i, tp in ipairs(tabs) do
        if tp == cur then
            from = i - 1
            break
        end
    end

    return M.focus(tabs[(from + step) % #tabs + 1])
end

-- NOTE: the sole caller is config/skills/_lib/driver.lua, off the runtimepath.
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
        vim.api.nvim_set_current_tabpage(saved_tab)
    end

    if vim.api.nvim_win_is_valid(saved_win) then
        vim.api.nvim_set_current_win(saved_win)
    end

    restore_terminal_focus()

    if not ok then
        return nil, tostring(result)
    end

    mark_dirty(name)

    return result
end

---Close the current user view.
---@return true? ok
---@return string? err
function M.close()
    local tp = vim.api.nvim_get_current_tabpage()
    local name = tab_view[tp]
    if name == nil then
        name = false
    end

    if #user_tabpages() <= 1 then
        return M.retire()
    end

    local bufs = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        bufs[#bufs + 1] = vim.api.nvim_win_get_buf(win)
    end
    local ok = pcall(vim.cmd.tabclose)
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
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    mark_dirty(name)

    return true
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
        materialize('edit')
        require('mux.session').mark_dirty()
        return
    end

    for i, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = names[i]
        tab_view[tp] = name and views[name] and name or false
    end

    local cur = vim.api.nvim_get_current_tabpage()
    for tp, name in pairs(tab_view) do
        if name and views[name].restore then
            vim.api.nvim_set_current_tabpage(tp)
            materialize(name)
        end
    end

    vim.api.nvim_set_current_tabpage(cur)
    vim.cmd.stopinsert()
    restore_terminal_focus()
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
        local view_name = tab_view[tp]
        local entry

        if view_name and views[view_name] then
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
        if not entry.persist and labels[entry.label] > 1 then
            entry.label = vim.api.nvim_tabpage_get_number(entry.tab)
                .. ':'
                .. entry.label
        end
    end

    return out
end

---@param buf integer
---@return nil
local function cleanup_terminal(buf)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_is_valid(win) then
            local tp = vim.api.nvim_win_get_tabpage(win)
            local name = tab_view[tp]
            local spec = name and views[name]

            if spec and spec.terminal then
                local has_terminal = false

                for _, other_win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
                    local other = vim.api.nvim_win_get_buf(other_win)
                    if other ~= buf and vim.bo[other].buftype == 'terminal' then
                        has_terminal = true
                        break
                    end
                end

                if has_terminal then
                    vim.api.nvim_win_close(win, true)
                elseif #user_tabpages() <= 1 then
                    M.retire()
                    return
                else
                    vim.api.nvim_set_current_tabpage(tp)
                    vim.cmd.tabclose()
                    tab_view[tp] = nil
                end
            end
        end
    end

    if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
        vim.api.nvim_buf_delete(buf, { force = true })
    end

    require('mux.session').mark_dirty()
end

---Signal a pty job's whole process group.
---Nvim setsid's pty children, so the job pid is its group leader. Signalling
---the job alone leaves grandchildren behind holding whatever the child held.
---@param pid integer
---@param signal string
---@return nil
local function kill_group(pid, signal)
    pcall(vim.system, { 'kill', '-' .. signal, '--', '-' .. pid })
end

---@param buf integer
---@return nil
local function reap_terminal(buf)
    local pid = term_pids[buf]
    term_pids[buf] = nil

    if not pid then
        return
    end

    kill_group(pid, 'TERM')
    vim.defer_fn(function()
        if vim.system({ 'kill', '-0', tostring(pid) }):wait().code == 0 then
            kill_group(pid, 'KILL')
        end
    end, JOB_EXIT_TIMEOUT_MS)
end

---@return nil
local function stop_terminals()
    local jobs = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local job = vim.b[buf].terminal_job_id
        if job then
            jobs[#jobs + 1] = job
            pcall(vim.fn.jobstop, job)
        end

        if term_pids[buf] then
            kill_group(term_pids[buf], 'TERM')
            term_pids[buf] = nil
        end
    end

    if #jobs > 0 then
        vim.fn.jobwait(jobs, JOB_EXIT_TIMEOUT_MS)
    end
end

---@return nil
local function setup_keymaps()
    for mode, rhs in pairs({
        n = '<c-w>',
        i = '<c-o><c-w>',
        t = '<c-\\><c-n><c-w>',
    }) do
        vim.keymap.set(mode, PREFIX, rhs, {
            remap = true,
            desc = 'mux: window command prefix',
        })
    end

    for _, entry in ipairs({
        { key = 'e', name = 'edit' },
        { key = 'v', name = 'vcs' },
        { key = 'z', name = 'zsh' },
    }) do
        vim.keymap.set(MODES, PREFIX .. entry.key, function()
            M.open(entry.name)
        end, { desc = 'mux: ' .. entry.name .. ' view', silent = true })
    end

    vim.keymap.set(MODES, PREFIX .. '[', function()
        walk(-vim.v.count1)
    end, { desc = 'mux: previous view', silent = true })
    vim.keymap.set(MODES, PREFIX .. ']', function()
        walk(vim.v.count1)
    end, { desc = 'mux: next view', silent = true })

    vim.keymap.set(MODES, PREFIX .. "'", '<cmd>vertical terminal<cr>', {
        desc = 'mux: vertical terminal',
        silent = true,
    })
    vim.keymap.set(MODES, PREFIX .. '-', '<cmd>split | terminal<cr>', {
        desc = 'mux: terminal',
        silent = true,
    })
    vim.keymap.set(MODES, PREFIX .. 'd', '<cmd>detach<cr>', {
        desc = 'mux: detach',
        silent = true,
    })
    vim.keymap.set(MODES, PREFIX .. 'x', function()
        M.close()
    end, { desc = 'mux: close view', silent = true })
    vim.keymap.set(MODES, PREFIX .. 'X', function()
        M.retire()
    end, { desc = 'mux: kill session', silent = true })
    vim.keymap.set(MODES, PREFIX .. 'b', function()
        require('mux.line').toggle()
    end, { desc = 'mux: toggle bar', silent = true })
    vim.keymap.set(MODES, PREFIX .. 'r', function()
        require('mux.server').reload()
    end, { desc = 'mux: reload', silent = true })
    vim.keymap.set(MODES, PREFIX .. 'R', function()
        local server = require('mux.server')
        local current = server.state().server
        if not current then
            return
        end

        for _, entry in ipairs(server.list()) do
            if
                entry.socket ~= current.socket
                and vim.uv.fs_stat(entry.socket)
            then
                local result = vim.system({
                    vim.v.progpath,
                    '--server',
                    entry.socket,
                    '--remote-expr',
                    "luaeval('require([[mux.server]]).reload()')",
                }, { text = true }):wait()
                if
                    result.code ~= 0
                    or vim.trim(result.stdout or '') ~= 'true'
                then
                    vim.notify(
                        ('mux: cannot restart %s'):format(server.label(entry)),
                        vim.log.levels.ERROR
                    )
                end
            end
        end
        server.reload()
    end, { desc = 'mux: reload all', silent = true })
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
    vim.api.nvim_create_autocmd('TermOpen', {
        group = group,
        callback = function(args)
            vim.bo[args.buf].bufhidden = 'wipe'
            local job = vim.b[args.buf].terminal_job_id
            local ok, pid = pcall(vim.fn.jobpid, job)

            if ok and type(pid) == 'number' and pid > 0 then
                term_pids[args.buf] = pid
            end
        end,
    })

    vim.api.nvim_create_autocmd({ 'BufHidden', 'BufWipeout', 'WinClosed' }, {
        group = group,
        callback = function()
            vim.schedule(function()
                for buf in pairs(term_pids) do
                    if
                        not vim.api.nvim_buf_is_valid(buf)
                        or #vim.fn.win_findbuf(buf) == 0
                    then
                        reap_terminal(buf)
                    end
                end
            end)
        end,
    })

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

    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            pcall(vim.api.nvim_del_augroup_by_id, group)
            stop_terminals()
        end,
    })
end

return M
