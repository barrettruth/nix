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
M.exit_to_latest = project.exit_to_latest

M.stop_session = session.stop_session
M.kill_session = session.kill_session
M.reload = session.reload
M.reload_all = session.reload_all
M.save_session = session.save_session
M.load_session = session.load_session

M.direnv_watch = direnv.watch

local bufremove = require('config.bufremove')

function M.bufdelete()
    bufremove(false)
end

function M.bufwipe()
    bufremove(true)
end

local AUTOSAVE_INTERVAL_MS = 5 * 60 * 1000

function M.setup()
    if M._did then
        return
    end
    M._did = true

    vim.o.sessionoptions =
        'buffers,curdir,folds,globals,help,tabpages,winsize,winpos'

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
        end, 'mux: move window ' .. key)
    end
    for name, spec in pairs(core.views) do
        local view_name = name
        muxmap(prefix .. spec.key, function()
            M.open_view(view_name)
        end, 'mux: ' .. view_name)
    end
    muxmap(prefix .. 'r', M.reload, 'mux: reload session (restart)')
    muxmap(prefix .. "'", function()
        vim.cmd('vsplit | terminal')
    end, 'mux: vertical terminal')
    muxmap(prefix .. '-', function()
        vim.cmd('split | terminal')
    end, 'mux: horizontal terminal')
    muxmap(prefix .. '<tab>', M.last_session, 'mux: last session')
    muxmap(prefix .. '<bs>', M.last_session, 'mux: last session')
    muxmap(prefix .. '^', M.last_view, 'mux: last view')
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
    muxmap(prefix .. 's', M.exit_to_latest, 'mux: stop session (hop to last)')
    muxmap(prefix .. 'x', M.close_view, 'mux: close view')
    muxmap(prefix .. 'X', M.exit_to_latest, 'mux: close session (hop to last)')
    muxmap(prefix .. 'R', M.reload_all, 'mux: reload all sessions (restart)')
    muxmap(prefix .. 'S', M.save_session, 'mux: save session')
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
    vim.api.nvim_create_autocmd(
        'TabClosed',
        { group = group, callback = core.prune }
    )
    vim.api.nvim_create_autocmd('TabEnter', {
        group = group,
        callback = function()
            vim.schedule(core.restore_terminal_focus)
        end,
    })
    vim.api.nvim_create_autocmd('UIEnter', {
        group = group,
        callback = line.refresh,
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
        end,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            session.save_session()
            session.clear_pid()
        end,
    })

    session.record_root()
    session.record_pid()

    if not session.load_session() then
        vim.cmd.edit(vim.fn.getcwd())
        core.tag(vim.api.nvim_get_current_tabpage(), 'edit')
    end

    M._timer = vim.uv.new_timer()
    M._timer:start(
        AUTOSAVE_INTERVAL_MS,
        AUTOSAVE_INTERVAL_MS,
        vim.schedule_wrap(function()
            session.save_session()
        end)
    )
end

return M
