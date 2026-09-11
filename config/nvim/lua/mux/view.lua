---@class mux.ViewEntry
---@field kind 'view'|'tab'
---@field name? string
---@field key? string
---@field persist? string|false Persisted tab identity; `false` preserves ordinary Vim tabs.
---@field label string
---@field tab integer
---@field current boolean

---@class mux.ViewSpec
---@field key string
---@field restore? boolean
---@field transient? boolean
---@field terminal? string[]

local M = {}

local JOB_EXIT_TIMEOUT_MS = 5000
local MODES = { 'n', 'i', 't' }
local PREFIX = '<a-x>'
local ai_command = vim.fn.executable('codex') == 1 and 'codex' or 'devin'
local zsh = vim.fn.exepath('zsh')

---@type table<string, mux.ViewSpec>
local views = {
    ai = { key = 'a', restore = true, terminal = { ai_command } },
    edit = { key = 'e' },
    direnv = { key = 'D', transient = true },
    vcs = { key = 'v', restore = true },
    zsh = { key = 'z', restore = true, terminal = { zsh } },
}

local did_setup = false

---Signal a pty job's whole process group.
---Nvim setsid's pty children, so the job pid is its group leader. Signalling
---the job alone leaves grandchildren behind holding whatever the child held.
---@param job integer
local function stop_job(job)
    local ok, pid = pcall(vim.fn.jobpid, job)
    if ok then
        vim.uv.kill(-pid, 'sigterm')
    end
    vim.fn.jobstop(job)
end

---@return string
local function root()
    local state = require('mux.server').state()

    return (state.server and state.server.root) or vim.fn.getcwd()
end

---@param name string|false|nil
---@return nil
local function mark_dirty(name)
    if
        name == false or (name and views[name] and not views[name].transient)
    then
        require('mux.session').mark_dirty()
    end
end

local function buffers(tab)
    return vim.iter(vim.api.nvim_tabpage_list_wins(tab))
        :filter(function(win)
            return vim.api.nvim_win_get_config(win).relative == ''
        end)
        :map(vim.api.nvim_win_get_buf)
        :totable()
end

local function normalize(tab)
    local name = vim.t[tab].mux_view
    local spec = name and views[name]
    if not spec or not (spec.transient or spec.terminal) then
        return
    end
    local owned, user = false, false
    for _, buf in ipairs(buffers(tab)) do
        if vim.b[buf].mux_view == name then
            owned = true
        elseif
            vim.bo[buf].buftype == ''
            or vim.api.nvim_buf_get_name(buf) ~= ''
        then
            user = true
        end
    end
    if user and not owned then
        vim.t[tab].mux_view = nil
        mark_dirty(false)
    end
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
    local name = vim.t[tp].mux_view
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
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        if vim.t[tp].mux_view == name then
            return tp
        end
    end
end

---@return integer[]
function M.transient_tabs()
    return vim.iter(vim.api.nvim_list_tabpages())
        :filter(function(tp)
            local name = vim.t[tp].mux_view
            return (name and views[name] and views[name].transient) == true
        end)
        :totable()
end

---@param buf integer
---@param status integer
---@return nil
local function finish_terminal(buf, status)
    if status ~= 0 or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_is_valid(win) then
            local tp = vim.api.nvim_win_get_tabpage(win)
            local name = vim.t[tp].mux_view
            local spec = name and views[name]
            local has_other = vim.iter(buffers(tp)):any(function(other)
                return other ~= buf
            end)

            if spec and spec.terminal and not has_other then
                M.close(tp)
                return
            end
        end
    end

    M.close_buffer(buf)
end

---@param name string
---@return nil
local function materialize(name)
    local cwd = root()
    local spec = views[name]

    if spec.terminal then
        for _, buf in ipairs(buffers(vim.api.nvim_get_current_tabpage())) do
            if vim.b[buf].mux_view == name then
                return
            end
        end
        local command = name == 'zsh'
                and require('mux.direnv').unload(spec.terminal)
            or spec.terminal
        local current = vim.api.nvim_get_current_buf()
        local buf = (
            vim.api.nvim_buf_get_name(current) ~= '' or vim.bo[current].modified
        )
                and vim.api.nvim_create_buf(false, true)
            or current
        vim.b[buf].mux_view = name
        local win = vim.api.nvim_get_current_win()
        if buf ~= current then
            win = vim.api.nvim_open_win(
                buf,
                false,
                { split = 'below', win = win }
            )
        end
        vim.api.nvim_win_call(win, function()
            vim.fn.jobstart(command, {
                term = true,
                cwd = cwd,
                on_exit = vim.schedule_wrap(function(_, status)
                    finish_terminal(buf, status)
                end),
            })
        end)
        restore_terminal_focus()
    elseif name == 'edit' then
        vim.cmd.edit(vim.fn.fnameescape(cwd))
    elseif name == 'vcs' then
        pcall(function()
            vim.cmd.Git()
            vim.cmd.only()
        end)
    end
end

---@param name string
---@param enter boolean
---@param buf? integer
---@return integer win
---@return integer tab
local function create(name, enter, buf)
    buf = buf or vim.api.nvim_create_buf(false, true)
    local tp = vim.api.nvim_open_tabpage(buf, enter, {})
    vim.t[tp].mux_view = name
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
    local spec = views[name]
    if not spec then
        return nil, nil, 'unknown view: ' .. tostring(name)
    end

    local tp = find(name)
    if tp then
        return vim.api.nvim_tabpage_get_win(tp), tp
    end
    if spec.transient then
        return nil, nil, 'view has no output: ' .. name
    end

    return create(name, false)
end

---@return (string|false)[]? labels
---@return string? err
function M.prepare_save()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        normalize(tab)
    end
    for _, tab in ipairs(M.transient_tabs()) do
        local name = vim.t[tab].mux_view
        for _, buf in ipairs(buffers(tab)) do
            if vim.b[buf].mux_view == name then
                M.close_buffer(buf)
            end
        end
        if vim.api.nvim_tabpage_is_valid(tab) then
            normalize(tab)
            if vim.t[tab].mux_view == name then
                local ok, err = M.close(tab)
                if not ok then
                    return nil, err
                end
            end
        end
    end
    return vim.tbl_map(function(entry)
        return entry.persist or false
    end, M.list())
end

---@param buf? integer
function M.close_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local current = vim.api.nvim_get_current_tabpage()
    if
        #vim.api.nvim_list_tabpages() == 1
        and #M.transient_tabs() > 0
        and vim.iter(buffers(current)):all(function(other)
            return other == buf
        end)
    then
        M.ensure('edit')
    end
    local job = vim.b[buf].terminal_job_id
    if job then
        stop_job(job)
    end
    vim.api.nvim_buf_delete(buf, { force = true })
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        normalize(tab)
    end
    if not vim.api.nvim_tabpage_is_valid(current) then
        M.focus(vim.api.nvim_get_current_tabpage())
    end
end

---@param name string
---@param buf integer
---@param previous? integer
---@return integer? win
---@return string? err
function M.mount(name, buf, previous)
    if not views[name] or not views[name].transient then
        return nil, 'not a transient view: ' .. tostring(name)
    end
    vim.b[buf].mux_view = name
    local tab = find(name)
    local win
    if tab then
        local replace = previous
            and vim.iter(vim.fn.win_findbuf(previous)):find(function(candidate)
                return vim.api.nvim_win_get_tabpage(candidate) == tab
            end)
        win = replace or vim.api.nvim_tabpage_get_win(tab)
        if replace then
            vim.api.nvim_win_set_buf(win, buf)
        else
            win = vim.api.nvim_open_win(
                buf,
                false,
                { split = 'below', win = win }
            )
        end
    else
        win, tab = create(name, false, buf)
        M.focus(tab)
        vim.cmd.stopinsert()
    end
    M.close_buffer(previous)
    return win
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
    mark_dirty(vim.t[tab].mux_view or false)

    return true
end

---@param step integer
---@return true? ok
---@return string? err
local function walk(step)
    local tabs = vim.api.nvim_list_tabpages()
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
    local win, _, err = M.ensure(name)
    if not win then
        return nil, err
    end

    local ok, result = pcall(vim.api.nvim_win_call, win, fn)

    restore_terminal_focus()

    if not ok then
        return nil, tostring(result)
    end

    mark_dirty(name)

    return result
end

---Close the current user view.
---@param tab? integer
---@return true? ok
---@return string? err
function M.close(tab)
    local current = vim.api.nvim_get_current_tabpage()
    local tp = tab or current
    local name = vim.t[tp].mux_view
    if name == nil then
        name = false
    end

    local spec = name and views[name]
    if spec and spec.transient then
        if #vim.api.nvim_list_tabpages() <= 1 then
            M.ensure('edit')
        end
    elseif #vim.api.nvim_list_tabpages() - #M.transient_tabs() <= 1 then
        return M.retire()
    end

    local bufs = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        bufs[#bufs + 1] = vim.api.nvim_win_get_buf(win)
    end
    local ok =
        pcall(vim.cmd.tabclose, tostring(vim.api.nvim_tabpage_get_number(tp)))
    if not ok then
        return nil, 'failed to close view'
    end

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
    if spec and spec.transient and tp == current then
        restore_terminal_focus()
    end

    return true
end

---Restore saved labels or bootstrap the default edit view.
---`nil` means no saved session; `false` means ordinary Vim tab.
---@param names (string|false)[]?
---@return nil
function M.restore(names)
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        vim.t[tp].mux_view = nil
    end

    if not names then
        local tp = vim.api.nvim_get_current_tabpage()
        vim.t[tp].mux_view = 'edit'
        materialize('edit')
        require('mux.session').mark_dirty()
        return
    end

    for i, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = names[i]
        vim.t[tp].mux_view = name and views[name] and name or false
    end

    local cur = vim.api.nvim_get_current_tabpage()
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local name = vim.t[tp].mux_view
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
        local view_name = vim.t[tp].mux_view
        local entry

        if view_name and views[view_name] then
            entry = {
                kind = 'view',
                name = view_name,
                key = views[view_name].key,
                persist = not views[view_name].transient and view_name or nil,
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

---@return nil
local function stop_terminals()
    local jobs = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local job = vim.b[buf].terminal_job_id
        if job then
            jobs[#jobs + 1] = job
            stop_job(job)
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

    for name, spec in pairs(views) do
        vim.keymap.set(MODES, PREFIX .. spec.key, function()
            M.open(name)
        end, { desc = 'mux: ' .. name .. ' view', silent = true })
    end

    vim.keymap.set(MODES, PREFIX .. '[', function()
        walk(-vim.v.count1)
    end, { desc = 'mux: previous view', silent = true })
    vim.keymap.set(MODES, PREFIX .. ']', function()
        walk(vim.v.count1)
    end, { desc = 'mux: next view', silent = true })

    vim.keymap.set(MODES, PREFIX .. "'", function()
        vim.cmd.vnew()
        materialize('zsh')
        if vim.bo.buftype == 'terminal' then
            vim.cmd.startinsert()
        end
    end, {
        desc = 'mux: vertical terminal',
        silent = true,
    })
    vim.keymap.set(MODES, PREFIX .. '-', function()
        vim.cmd.new()
        materialize('zsh')
        if vim.bo.buftype == 'terminal' then
            vim.cmd.startinsert()
        end
    end, {
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
    vim.api.nvim_create_autocmd('BufWinEnter', {
        group = group,
        callback = function(args)
            for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
                normalize(vim.api.nvim_win_get_tabpage(win))
            end
        end,
    })
    vim.api.nvim_create_autocmd('BufWinLeave', {
        group = group,
        callback = function(args)
            local job = vim.b[args.buf].terminal_job_id
            if job and #vim.fn.win_findbuf(args.buf) == 1 then
                stop_job(job)
            end
        end,
    })
    vim.api.nvim_create_autocmd('TermOpen', {
        group = group,
        callback = function(args)
            vim.bo[args.buf].bufhidden = 'wipe'
        end,
    })

    vim.api.nvim_create_autocmd({ 'BufHidden', 'BufWipeout', 'WinClosed' }, {
        group = group,
        callback = function()
            vim.schedule(function()
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if
                        vim.bo[buf].buftype == 'terminal'
                        and (vim.b[buf].terminal_job_id or vim.b[buf].mux_view)
                        and #vim.fn.win_findbuf(buf) == 0
                    then
                        M.close_buffer(buf)
                    end
                end
            end)
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
