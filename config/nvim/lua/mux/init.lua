-- mux: in-Neovim "multiplexer" brain. Each "view" is a tagged tabpage; switching
-- projects is `:connect` to another per-project nvim server (see scripts/mux).

local core = require('mux.core')
local view = require('mux.view')
local project = require('mux.project')
local session = require('mux.session')

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
M.save_session = session.save_session
M.load_session = session.load_session

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
    for name, spec in pairs(core.views) do
        vim.keymap.set(
            { 'n', 'i', 't' },
            prefix .. spec.key,
            ('<cmd>lua require("mux").open_view(%q)<cr>'):format(name),
            { desc = 'mux: ' .. name }
        )
    end
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. '<tab>',
        [[<cmd>lua require('mux').last_session()<cr>]],
        { desc = 'mux: last session' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. '<bs>',
        [[<cmd>lua require('mux').last_view()<cr>]],
        { desc = 'mux: last view' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'm',
        [[<cmd>lua require('mux').pick_project()<cr>]],
        { desc = 'mux: switch project' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. ']',
        [[<cmd>lua require('mux').cycle_project(1)<cr>]],
        { desc = 'mux: next project' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. '[',
        [[<cmd>lua require('mux').cycle_project(-1)<cr>]],
        { desc = 'mux: previous project' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'd',
        '<cmd>detach<cr>',
        { desc = 'mux: detach to shell' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 's',
        [[<cmd>lua require('mux').exit_to_latest()<cr>]],
        { desc = 'mux: stop session (hop to last)' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'x',
        [[<cmd>lua require('mux').close_view()<cr>]],
        { desc = 'mux: close view' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'X',
        [[<cmd>lua require('mux').exit_to_latest()<cr>]],
        { desc = 'mux: close session (hop to last)' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'R',
        [[<cmd>lua require('mux').reload()<cr>]],
        { desc = 'mux: reload session (restart)' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'S',
        [[<cmd>lua require('mux').save_session()<cr>]],
        { desc = 'mux: save session' }
    )

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

    vim.api.nvim_create_autocmd('TermClose', {
        group = group,
        callback = function(args)
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
