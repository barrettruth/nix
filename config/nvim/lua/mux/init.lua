-- mux: in-Neovim "multiplexer" brain. Each "view" is a tagged tabpage; switching
-- projects is `:connect` to another per-project nvim server (see scripts/mux).

local core = require('mux.core')
local view = require('mux.view')
local project = require('mux.project')
local session = require('mux.session')
local direnv = require('mux.direnv')
local line = require('mux.line')

local M = {}

M.views = core.views

M.open_view = view.open_view
M.resolve_view = view.resolve_view
M.in_view = view.in_view
M.state = view.state
M.last_view = view.last_view
M.close_view = view.close_view

M._connect = project._connect
M.pick_project = project.pick_project
M.cycle_project = project.cycle_project
M.list_entries = project.list_entries
M.last_session = project.last_session
M.stop_to_latest = project.stop_to_latest
M.kill_to_latest = project.kill_to_latest

M.stop_session = session.stop_session
M.kill_session = session.kill_session
M.reload = session.reload
M.reload_all = session.reload_all
M.save_session = session.save_session
M.load_session = session.load_session
M.mark_dirty = session.mark_dirty
M.flush_session = session.flush_session

M.direnv_watch = direnv.watch

local bufremove = require('config.bufremove')

function M.bufdelete()
    bufremove(false)
    session.mark_dirty()
end

function M.bufwipe()
    bufremove(true)
    session.mark_dirty()
end

local function disable_terminal_color_request_handler()
    local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
        group = 'nvim.terminal',
        event = 'TermRequest',
    })
    if not ok then
        return
    end
    for _, autocmd in ipairs(autocmds) do
        if
            autocmd.desc == 'Handles OSC foreground/background color requests'
        then
            pcall(vim.api.nvim_del_autocmd, autocmd.id)
        end
    end
end

function M.setup()
    if M._did then
        return
    end
    M._did = true

    vim.o.sessionoptions =
        'buffers,curdir,folds,globals,help,tabpages,winsize,winpos'
    disable_terminal_color_request_handler()

    local prefix = '<a-x>'
    local modes = { 'n', 'i', 't' }

    ---@param lhs string
    ---@param rhs fun()
    ---@param desc string
    local function muxmap(lhs, rhs, desc)
        vim.keymap.set(modes, lhs, function()
            rhs()
            line.refresh()
        end, { desc = desc })
    end

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
    for _, key in ipairs({ 'H', 'J', 'K', 'L' }) do
        muxmap(prefix .. key, function()
            vim.cmd('wincmd ' .. key)
            session.mark_dirty()
        end, 'mux: move window ' .. key)
    end
    for name, spec in pairs(core.views) do
        local view_name = name
        muxmap(prefix .. spec.key, function()
            M.open_view(view_name)
        end, 'mux: ' .. view_name)
    end
    for _, name in ipairs({ 'run', 'build', 'test' }) do
        local view_name = name
        local key = core.views[view_name].key
        muxmap(prefix .. '<c-' .. key .. '>', function()
            M.open_view(view_name)
        end, 'mux: ' .. view_name)
    end
    muxmap(prefix .. 'r', M.reload, 'mux: reload session (restart)')
    muxmap(prefix .. "'", function()
        vim.cmd('vsplit | terminal')
        session.mark_dirty()
    end, 'mux: vertical terminal')
    muxmap(prefix .. '-', function()
        vim.cmd('split | terminal')
        session.mark_dirty()
    end, 'mux: horizontal terminal')
    muxmap(prefix .. '<tab>', M.last_session, 'mux: last session')
    muxmap(prefix .. '<bs>', M.last_session, 'mux: last session')
    muxmap(prefix .. '6', M.last_view, 'mux: last view')
    muxmap(prefix .. 'm', M.pick_project, 'mux: switch project')
    muxmap(prefix .. ']', function()
        M.cycle_project(1)
    end, 'mux: next project')
    muxmap(prefix .. '[', function()
        M.cycle_project(-1)
    end, 'mux: previous project')
    muxmap(prefix .. 'd', function()
        vim.cmd('detach')
    end, 'mux: detach to shell')
    muxmap(prefix .. 's', M.save_session, 'mux: save session')
    muxmap(prefix .. 'x', M.close_view, 'mux: close view')
    muxmap(prefix .. 'X', M.kill_to_latest, 'mux: kill session (hop to last)')
    muxmap(prefix .. 'R', M.reload_all, 'mux: reload all sessions (restart)')
    muxmap(prefix .. 'S', M.stop_to_latest, 'mux: stop session (hop to last)')
    muxmap(prefix .. 'B', line.toggle, 'mux: toggle mux bar')

    pcall(vim.keymap.del, 'n', '<leader>bd')
    pcall(vim.keymap.del, 'n', '<leader>bw')
    vim.cmd(
        [[cnoreabbrev <expr> bd (getcmdtype()==':' && getcmdline()==#'bd') ? "lua require('mux').bufdelete()" : 'bd']]
    )
    vim.cmd(
        [[cnoreabbrev <expr> bw (getcmdtype()==':' && getcmdline()==#'bw') ? "lua require('mux').bufwipe()" : 'bw']]
    )

    local group = vim.api.nvim_create_augroup('mux', { clear = true })
    line.apply_visibility()
    vim.api.nvim_create_autocmd('TabClosed', {
        group = group,
        callback = function()
            core.prune()
            line.refresh()
            session.mark_dirty()
        end,
    })
    vim.api.nvim_create_autocmd({ 'TabNew', 'DirChanged' }, {
        group = group,
        callback = function()
            line.refresh()
            session.mark_dirty()
        end,
    })
    vim.api.nvim_create_autocmd(
        { 'WinNew', 'WinClosed', 'BufAdd', 'BufDelete' },
        {
            group = group,
            callback = session.mark_dirty,
        }
    )
    vim.api.nvim_create_autocmd('TabEnter', {
        group = group,
        callback = function()
            vim.schedule(core.restore_terminal_focus)
            line.refresh()
        end,
    })
    vim.api.nvim_create_autocmd('UIEnter', {
        group = group,
        callback = function()
            line.apply_visibility()
            line.refresh()
        end,
    })

    vim.api.nvim_create_autocmd('TermClose', {
        group = group,
        callback = function(args)
            if not vim.api.nvim_buf_is_valid(args.buf) then
                return
            end
            local ok, is_direnv_watch =
                pcall(vim.api.nvim_buf_get_var, args.buf, 'mux_direnv_watch')
            if ok and is_direnv_watch then
                vim.schedule(function()
                    for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
                        if vim.api.nvim_win_is_valid(win) then
                            pcall(vim.api.nvim_win_close, win, true)
                        end
                    end
                    if vim.api.nvim_buf_is_valid(args.buf) then
                        pcall(
                            vim.api.nvim_buf_delete,
                            args.buf,
                            { force = true }
                        )
                    end
                end)
                return
            end
            for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
                local tp = vim.api.nvim_win_get_tabpage(win)
                local name = core.tab_view[tp]
                if
                    name
                    and core.views[name]
                    and core.views[name].lifecycle == 'ephemeral'
                then
                    view.on_ephemeral_exit(win, args.buf)
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd('TabLeave', {
        group = group,
        callback = function()
            view._alt = vim.api.nvim_get_current_tabpage()
            line.refresh()
        end,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            line.stop_watchers()
            session.save_session()
            session.clear_pid()
        end,
    })

    session.record_root()
    session.record_pid()
    line.start_watchers()

    if not session.load_session() then
        vim.cmd.edit(vim.fn.getcwd())
        core.tag(vim.api.nvim_get_current_tabpage(), 'edit')
    end
    line.refresh()
end

return M
