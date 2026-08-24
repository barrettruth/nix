local M = {}

local SAVE_DEBOUNCE_MS = 3000
local dirty = false
local restoring = false
local saving = false
local save_timer
local did_setup = false

---@return mux.Server? server
---@return string? err
local function current()
    local server = require('mux.server').state().server
    if not server then
        return nil, 'not a mux server'
    end
    return server
end

local function stop_save_timer(close)
    local timer = save_timer
    if not timer then
        return
    end
    timer:stop()
    if close then
        save_timer = nil
        timer:close()
    end
end

local function schedule_save()
    stop_save_timer()
    save_timer = save_timer or vim.uv.new_timer()
    save_timer:start(
        SAVE_DEBOUNCE_MS,
        0,
        vim.schedule_wrap(function()
            if dirty then
                M.save()
            end
        end)
    )
end

---Mark persistent user session state dirty and debounce a save.
---@return nil
function M.mark_dirty()
    if restoring or saving then
        return
    end
    dirty = true
    schedule_save()
end

---Persist the current user view layout to the server session file.
---@return true? ok
---@return string? err
function M.save()
    local server, err = current()
    if not server then
        return nil, err
    end
    dirty = false
    stop_save_timer(true)
    local labels = {}
    for _, entry in ipairs(require('mux.view').list()) do
        if entry.persist ~= nil then
            labels[#labels + 1] = entry.persist or false
        end
    end
    vim.g.Mux = vim.json.encode({ root = server.root, tabs = labels })
    local dir = vim.fn.fnamemodify(server.session, ':h')
    local mk_ok = pcall(vim.fn.mkdir, dir, 'p')
    if not mk_ok then
        return nil, 'failed to create session directory: ' .. dir
    end
    saving = true
    local ok =
        pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(server.session))
    saving = false
    if not ok then
        return nil, 'failed to write session: ' .. server.session
    end
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
    dirty = false
    stop_save_timer(true)
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
    restoring = true
    local ok =
        pcall(vim.cmd, 'silent! source ' .. vim.fn.fnameescape(server.session))
    if not ok then
        restoring = false
        return nil, 'failed to restore session: ' .. server.session
    end
    local mux = vim.g.Mux and vim.json.decode(vim.g.Mux)
    require('mux.view').restore(mux and mux.tabs)
    restoring = false
    return true
end

---Install session dirty tracking and leave-time persistence hooks.
---@return nil
function M.setup()
    if did_setup then
        return
    end
    did_setup = true
    local group = vim.api.nvim_create_augroup('mux-session', { clear = true })
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
            M.save()
        end,
    })
end

return M
