local M = {}

local SAVE_DEBOUNCE_MS = 3000
local dirty = false
local restoring = false
local save_timer
local did_setup = false

local function server_record()
    local server = require('mx.server')._record()
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

---@return nil
function M.mark_dirty()
    if restoring then
        return
    end
    dirty = true
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

---@return true? ok
---@return string? err
function M.save()
    local server, err = server_record()
    if not server then
        return nil, err
    end
    dirty = false
    stop_save_timer(true)
    local ok_views, views = pcall(require('mx.view').ordered)
    if not ok_views then
        return nil, 'failed to encode mux views'
    end
    local ok_json, encoded = pcall(vim.json.encode, views)
    if not ok_json then
        return nil, 'failed to encode mux views'
    end
    vim.g.mux_views = encoded
    local dir = vim.fn.fnamemodify(server.session, ':h')
    local mk_ok = pcall(vim.fn.mkdir, dir, 'p')
    if not mk_ok then
        return nil, 'failed to create session directory: ' .. dir
    end
    local ok =
        pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(server.session))
    if not ok then
        return nil, 'failed to write session: ' .. server.session
    end
    return true
end

---@return true? ok
---@return string? err
function M.restore()
    local server, err = server_record()
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
    local names = {}
    local raw = vim.g.mux_views
    if type(raw) == 'string' and raw ~= '' then
        local ok_json, decoded = pcall(vim.json.decode, raw)
        if ok_json and type(decoded) == 'table' then
            names = decoded
        end
    end
    require('mx.view').restore(names)
    restoring = false
    return true
end

---@return nil
function M.setup()
    if did_setup then
        return
    end
    did_setup = true
    local group = vim.api.nvim_create_augroup('mx-session', { clear = true })
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
