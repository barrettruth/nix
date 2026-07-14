local server = require('mux.server')
local view = require('mux.view')

local M = {}

local TABLINE_EXPR = "%!v:lua.require'mux.line'.render()"

---@type mux.Server[]
local cached_servers = {}

local redraw_pending = false

---@return nil
local function apply_visibility()
    local file = server.runtime_dir() .. '/mux-bar'
    local hide = vim.fn.filereadable(file) == 1
        and vim.fn.readfile(file)[1] == 'hide'
    vim.o.tabline = TABLINE_EXPR
    vim.o.showtabline = hide and 0 or 2
end

---@return string[]
local function view_segments()
    local parts = {}
    for _, entry in ipairs(view.list()) do
        parts[#parts + 1] = ('%%#%s#%s%%*'):format(
            entry.current and 'TabLineSel' or 'TabLine',
            entry.name
        )
    end
    return parts
end

---@return string[]
local function session_segments()
    local current = server._record()
    local parts = {}
    for _, entry in ipairs(cached_servers) do
        local name = vim.fn.fnamemodify(entry.root, ':t')
        if name ~= '' then
            local group = current
                    and current.root == entry.root
                    and 'TabLineSel'
                or 'TabLine'
            parts[#parts + 1] = ('%%#%s#%s%%*'):format(group, name)
        end
    end
    return parts
end

---@return nil
function M.update_servers()
    cached_servers = server.list()
    table.sort(cached_servers, function(a, b)
        return a.root < b.root
    end)
    M.redraw()
end

---@return nil
function M.redraw()
    if vim.in_fast_event() then
        vim.schedule(M.redraw)
        return
    end
    if redraw_pending then
        return
    end
    redraw_pending = true
    vim.schedule(function()
        redraw_pending = false
        apply_visibility()
        pcall(vim.cmd.redrawtabline)
        pcall(vim.cmd.redrawstatus)
    end)
end

---@return string
function M.render()
    if not server._record() then
        return ''
    end
    return (' %s%%=%s '):format(
        table.concat(view_segments(), ' '),
        table.concat(session_segments(), ' ')
    )
end

---@return true? ok
---@return string? err
function M.toggle()
    if not server._record() then
        return nil, 'not a mux server'
    end
    local file = server.runtime_dir() .. '/mux-bar'
    pcall(vim.fn.mkdir, vim.fn.fnamemodify(file, ':h'), 'p')
    pcall(
        vim.fn.writefile,
        { vim.o.showtabline == 0 and 'show' or 'hide' },
        file
    )
    M.redraw()
    return true
end

---@param step integer
---@return true? ok
---@return string? err
function M.cycle(step)
    M.update_servers()
    local current = server._record()
    if not current or #cached_servers == 0 then
        return nil, 'not a mux server'
    end
    local idx = 1
    for i, entry in ipairs(cached_servers) do
        if entry.root == current.root then
            idx = i
            break
        end
    end
    local target = ((idx - 1 + step) % #cached_servers) + 1
    local entry = cached_servers[target]
    if entry and entry.socket and entry.root ~= current.root then
        local ok, err =
            pcall(vim.cmd, 'connect ' .. vim.fn.fnameescape(entry.socket))
        if not ok then
            return nil, tostring(err)
        end
    end
    return true
end

---@return nil
function M.setup()
    apply_visibility()
    local group = vim.api.nvim_create_augroup('mux-line', { clear = true })
    vim.api.nvim_create_autocmd({ 'TabEnter', 'TabNew', 'TabClosed' }, {
        group = group,
        callback = M.redraw,
    })
    vim.api.nvim_create_autocmd('UIEnter', {
        group = group,
        callback = function()
            M.update_servers()
        end,
    })
end

return M
