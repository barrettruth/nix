local M = {}

local SAVE_DEBOUNCE_MS = 3000
local dirty = false
local restoring = false
local saving = false
local suppress_dirty = 0
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
    pcall(timer.stop, timer)
    if close then
        save_timer = nil
        pcall(timer.close, timer)
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

---@return nil
function M.mark_dirty()
    if restoring or saving or suppress_dirty > 0 then
        return
    end
    dirty = true
    schedule_save()
end

---@generic T
---@param fn fun(): T
---@return T
function M.without_dirty(fn)
    suppress_dirty = suppress_dirty + 1
    local result = { pcall(fn) }
    suppress_dirty = suppress_dirty - 1
    if not result[1] then
        error(result[2])
    end
    return unpack(result, 2)
end

---@param force? boolean
---@return true? ok
---@return string? err
function M.save(force)
    local server, err = current()
    if not server then
        return nil, err
    end
    if not force and require('mux.view').has_internal() then
        schedule_save()
        return true
    end
    dirty = false
    stop_save_timer(true)
    local views = require('mux.view').ordered()
    vim.g.Mux = vim.json.encode({ views = views })
    local dir = vim.fn.fnamemodify(server.session, ':h')
    local mk_ok = pcall(vim.fn.mkdir, dir, 'p')
    if not mk_ok then
        return nil, 'failed to create session directory: ' .. dir
    end
    saving = true
    local ok_wrap, ok = pcall(require('mux.view').without_internal, function()
        return pcall(
            vim.cmd,
            'mksession! ' .. vim.fn.fnameescape(server.session)
        )
    end)
    saving = false
    if not ok_wrap then
        return nil, tostring(ok)
    end
    if not ok then
        return nil, 'failed to write session: ' .. server.session
    end
    return true
end

---@return true? ok
---@return string? err
function M.forget()
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
    local mux = vim.g.Mux and vim.json.decode(vim.g.Mux) or {}
    require('mux.view').restore(mux.views)
    restoring = false
    return true
end

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
