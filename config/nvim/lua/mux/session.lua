local M = {}

local restoring = false
local saving = false
local save_timer
local enabled = false

---@return mux.Server? server
---@return string? err
local function current()
    local server = require('mux.server').state().server
    if not server then
        return nil, 'not a mux server'
    end

    return server
end

local function stop_save_timer()
    local timer = save_timer
    save_timer = nil
    if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
    end
end

local function schedule_save()
    stop_save_timer()
    local timer
    timer = vim.defer_fn(function()
        if not enabled or save_timer ~= timer then
            return
        end
        local ok, err = M.save()
        if not ok then
            vim.notify('mux: ' .. err, vim.log.levels.WARN)
        end
    end, 3000)
    save_timer = timer
end

---Mark persistent user session state dirty and debounce a save.
---@return nil
function M.mark_dirty()
    if not enabled or restoring or saving then
        return
    end

    schedule_save()
end

local function prepare(server)
    local labels, err = require('mux.view').prepare_save()
    if not labels then
        return nil, err
    end
    local terminals = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local kind = vim.b[buf].mux_terminal
        if kind and vim.bo[buf].buftype == 'terminal' then
            terminals[vim.api.nvim_buf_get_name(buf)] = kind
        end
    end
    vim.g.Mux = vim.json.encode({
        root = server.root,
        tabs = labels,
        terminals = terminals,
    })
    return true
end

---Persist the current user view layout to the server session file.
---@param force? boolean
---@return true? ok
---@return string? err
function M.save(force)
    local server, err = current()
    if not server then
        return nil, err
    end

    local view = require('mux.view')
    local transient = view.transient_tabs()
    if #transient > 0 and not force then
        schedule_save()
        return true
    end

    M.setup()

    local dir = vim.fn.fnamemodify(server.session, ':h')
    local mk_ok = pcall(vim.fn.mkdir, dir, 'p')

    if not mk_ok then
        return nil, 'failed to create session directory: ' .. dir
    end

    saving = true
    local ok = pcall(
        vim.cmd.mksession,
        { vim.fn.fnameescape(server.session), bang = true }
    )
    saving = false

    if not ok then
        return nil, 'failed to write session: ' .. server.session
    end
    stop_save_timer()

    return true
end

---Delete the saved session file and stop persistence hooks.
---@return true? ok
---@return string? err
function M.delete()
    local server, err = current()
    if not server then
        return nil, err
    end

    if
        vim.fn.filereadable(server.session) == 1
        and vim.fn.delete(server.session) ~= 0
    then
        return nil, 'failed to delete session: ' .. server.session
    end

    enabled = false
    stop_save_timer()
    pcall(vim.api.nvim_del_augroup_by_name, 'mux-session')

    return true
end

---Source the saved session and reattach mux view identities.
---@return true? ok
---@return string? err
function M.restore()
    local server, err = current()
    if not server then
        return nil, err
    end

    if vim.fn.filereadable(server.session) == 0 then
        return nil, 'no session'
    end

    M.setup()
    restoring = true
    local ok, source_err = pcall(vim.cmd.source, {
        vim.fn.fnameescape(server.session),
        mods = { silent = true },
    })
    restoring = false
    if not ok then
        return nil, tostring(source_err)
    end

    return true
end

---Install session dirty tracking and leave-time persistence hooks.
---@return nil
function M.setup()
    if enabled then
        return
    end

    enabled = true
    local group = vim.api.nvim_create_augroup('mux-session', { clear = true })
    vim.api.nvim_create_autocmd('SessionWritePre', {
        group = group,
        nested = true,
        callback = function()
            assert(prepare(assert(current())))
        end,
    })
    vim.api.nvim_create_autocmd('SourcePost', {
        group = group,
        nested = true,
        callback = function(args)
            if vim.v.exiting ~= vim.NIL or args.file ~= vim.v.this_session then
                return
            end
            local server = current()
            local mux = vim.g.Mux and vim.json.decode(vim.g.Mux)
            if not server or not mux or mux.root ~= server.root then
                return
            end
            local previous = restoring
            restoring = true
            local ok, err =
                pcall(require('mux.view').restore, mux.tabs, mux.terminals)
            restoring = previous
            if not ok then
                error(err)
            end
        end,
    })
    vim.api.nvim_create_autocmd({
        'TabNew',
        'TabClosed',
        'WinNew',
        'WinClosed',
        'WinResized',
        'BufAdd',
        'BufDelete',
        'BufFilePost',
        'DirChanged',
    }, {
        group = group,
        callback = M.mark_dirty,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            M.save(true)
        end,
    })
end

return M
