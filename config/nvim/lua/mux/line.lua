local server = require('mux.server')
local view = require('mux.view')

local M = {}

local TABLINE_EXPR = "%!v:lua.require'mux.line'.render()"
local VIEW_CLICK = "v:lua.require'mux.line'.on_view"
local SESSION_CLICK = "v:lua.require'mux.line'.on_session"

---@type mux.Server[]
local cached_servers = {}

local redraw_pending = false

---@return mux.Server[]
function M.servers()
    local servers = server.list()
    table.sort(servers, function(a, b)
        return a.root < b.root
    end)

    return servers
end

---@return nil
local function apply_visibility()
    local file = server.state().runtime_dir .. '/mux-bar'
    local hide = vim.fn.filereadable(file) == 1
        and vim.fn.readfile(file)[1] == 'hide'
    local showtabline = hide and 0 or 2
    vim.o.tabline = TABLINE_EXPR
    if vim.o.showtabline ~= showtabline then
        vim.o.showtabline = showtabline
    end
end

---@param minwid integer
---@param func string
---@param group string
---@param text string
---@return string
local function segment(minwid, func, group, text)
    local label = text:gsub('%%', '%%%%')

    return ('%%%d@%s@%%#%s#%s%%*%%X'):format(minwid, func, group, label)
end

---@return string[]
local function view_segments()
    local parts = {}
    for _, entry in ipairs(view.list()) do
        parts[#parts + 1] = segment(
            entry.tab,
            VIEW_CLICK,
            entry.current and 'TabLineSel' or 'TabLine',
            (entry.current and '*' or '') .. entry.label
        )
    end

    return parts
end

---@return string[]
local function session_segments()
    local current = server.state().server
    local parts = {}
    for i, entry in ipairs(cached_servers) do
        local name = vim.fn.fnamemodify(entry.root, ':t')

        if entry.host then
            name = ('%s:%s'):format(entry.host, name)
        end

        if name ~= '' then
            local selected = current and current.root == entry.root
            parts[#parts + 1] = segment(
                i,
                SESSION_CLICK,
                selected and 'TabLineSel' or 'TabLine',
                (selected and '*' or '') .. name
            )
        end
    end

    return parts
end

---Refresh cached line state and redraw.
---@return nil
function M.refresh()
    cached_servers = M.servers()
    M.redraw()
end

---Coalesce tabline redraws across fast events and autocmd bursts.
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

---Render user views on the left and mux servers on the right.
---@return string
function M.render()
    if not server.state().server then
        return ''
    end

    return (' %s%%=%s '):format(
        table.concat(view_segments(), ' '),
        table.concat(session_segments(), ' ')
    )
end

---Persistently toggle whether the mux line is shown.
---@return true? ok
---@return string? err
function M.toggle()
    local state = server.state()
    if not state.server then
        return nil, 'not a mux server'
    end

    local file = state.runtime_dir .. '/mux-bar'
    pcall(vim.fn.mkdir, vim.fn.fnamemodify(file, ':h'), 'p')
    pcall(
        vim.fn.writefile,
        { vim.o.showtabline == 0 and 'show' or 'hide' },
        file
    )
    M.redraw()

    return true
end

---@param entry mux.Server
local function connect(entry)
    server.attach(entry, function(ok, err)
        if not ok then
            vim.notify('mux: ' .. tostring(err), vim.log.levels.ERROR)
        end
    end)
end

---Tabline click handler for a view segment.
---@param tab integer
---@return nil
function M.on_view(tab)
    view.focus(tab)
end

---Tabline click handler for a session segment. Indexes the servers the
---segment was rendered from: a fresh list may have shifted under the label.
---@param index integer
---@return nil
function M.on_session(index)
    local current = server.state().server
    local entry = cached_servers[index]
    if not entry or (current and entry.root == current.root) then
        return
    end

    connect(entry)
end

---@param step integer
---@return true? ok
---@return string? err
local function move(step)
    M.refresh()
    local current = server.state().server
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
    if not entry or entry.root == current.root then
        return true
    end

    connect(entry)

    return true
end

---@param n integer
---@return true? ok
---@return string? err
local function move_to(n)
    M.refresh()
    local current = server.state().server
    if not current then
        return nil, 'not a mux server'
    end

    local entry = cached_servers[n]
    if not entry or entry.root == current.root then
        return true
    end

    connect(entry)

    return true
end

---@return true? ok
---@return string? err
local function move_last()
    M.refresh()
    local state = server.state()
    local current = state.server
    if not current then
        return nil, 'not a mux server'
    end

    local root = state.last_root
    if not root or root == current.root then
        return true
    end

    for _, entry in ipairs(cached_servers) do
        if entry.root == root then
            connect(entry)
            return true
        end
    end

    return nil, 'no server for ' .. root
end

---Install mux line visibility and redraw autocmds.
---@return nil
function M.setup()
    apply_visibility()
    for lhs, step in pairs({ ['<a-x>['] = -1, ['<a-x>]'] = 1 }) do
        vim.keymap.set({ 'n', 'i', 't' }, lhs, function()
            move(step * vim.v.count1)
        end, { desc = 'mux: move server', silent = true })
    end
    vim.keymap.set({ 'n', 'i', 't' }, '<a-x><bs>', function()
        move_last()
    end, { desc = 'mux: last server', silent = true })
    for n = 1, 9 do
        vim.keymap.set({ 'n', 'i', 't' }, '<a-x>' .. n, function()
            move_to(n)
        end, { desc = 'mux: server ' .. n, silent = true })
    end
    local group = vim.api.nvim_create_augroup('mux-line', { clear = true })
    vim.api.nvim_create_autocmd({ 'TabEnter', 'TabNew', 'TabClosed' }, {
        group = group,
        callback = M.redraw,
    })
    vim.api.nvim_create_autocmd('UIEnter', {
        group = group,
        callback = function()
            M.refresh()
        end,
    })
end

return M
