local server = require('mux.server')
local view = require('mux.view')

local M = {}

---@type mux.Server[]
local cached_servers = {}

local WATCH_MS = 150

---@type uv.uv_fs_event_t[]
local watchers = {}
local watch_timer = assert(vim.uv.new_timer())
local watched = ''

---The sorted names every session is known by.
---@return string
local function listing()
    local state = server.state()
    local names = vim.fn.glob(state.runtime_dir .. '/*.sock', true, true)
    vim.list_extend(
        names,
        vim.fn.glob(state.runtime_dir .. '/*/*.sock', true, true)
    )
    vim.list_extend(names, vim.fn.glob(state.state_dir .. '/*.vim', true, true))
    table.sort(names)

    return table.concat(names, '\n')
end

---@return nil
local function apply_visibility()
    local file = server.state().runtime_dir .. '/mux-bar'
    local hide = vim.fn.filereadable(file) == 1
        and vim.fn.readfile(file)[1] == 'hide'
    local showtabline = hide and 0 or 2

    vim.o.tabline = "%!v:lua.require'mux.line'.render()"

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
            "v:lua.require'mux.line'.on_view",
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
        local name = server.label(entry)

        if name ~= '' then
            local selected = current and current.root == entry.root
            parts[#parts + 1] = segment(
                i,
                "v:lua.require'mux.line'.on_session",
                selected and 'TabLineSel' or 'TabLine',
                ('%s%d:%s'):format(selected and '*' or '', i, name)
            )
        end
    end

    return parts
end

---Refresh cached line state and redraw.
---@return nil
function M.refresh()
    cached_servers = server.ordered()
    M.redraw()
end

local redraw_pending = false

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

---Tabline click handler for a view segment.
---@param tab integer
---@return nil
function M.on_view(tab)
    view.focus(tab)
end

---@param root string
---@return integer? index
local function index_of(root)
    for i, entry in ipairs(cached_servers) do
        if entry.root == root then
            return i
        end
    end
end

---Refresh, then go to whichever server `pick` names.
---@param pick fun(current: mux.Server): mux.Server?, string?
---@return true? ok
---@return string? err
local function jump(pick)
    M.refresh()

    local current = server.state().server

    if not current then
        return nil, 'not a mux server'
    end

    local entry, err = pick(current)

    if err then
        return nil, err
    end

    if entry and entry.root ~= current.root then
        server.switch(entry, function(ok, switch_err)
            if not ok then
                vim.notify(
                    'mux: ' .. tostring(switch_err),
                    vim.log.levels.ERROR
                )
            end
        end)
    end

    return true
end

---@param n integer
---@return true? ok
---@return string? err
local function move_to(n)
    return jump(function()
        return cached_servers[n]
    end)
end

---@return true? ok
---@return string? err
local function move_last()
    return jump(function(current)
        local root = server.state().last_root

        if not root or root == current.root then
            return nil
        end

        local index = index_of(root)

        if not index then
            return nil, 'no server for ' .. root
        end

        return cached_servers[index]
    end)
end

---Tabline click handler for a session segment. Indexes the servers the
---segment was rendered from: a fresh list may have shifted under the label.
---@param index integer
---@return nil
function M.on_session(index)
    local entry = cached_servers[index]

    jump(function()
        return entry
    end)
end

---@return nil
local function on_listing_change()
    local names = listing()

    if names == watched then
        return
    end

    watched = names
    M.refresh()
end

---Follow the directories a session appears in.
---@return nil
local function watch()
    local state = server.state()

    for _, handle in ipairs(watchers) do
        pcall(handle.stop, handle)
    end

    watchers = {}
    watched = listing()

    for _, dir in ipairs({ state.runtime_dir, state.state_dir }) do
        pcall(vim.fn.mkdir, dir, 'p')
        local handle = vim.uv.new_fs_event()

        if handle then
            handle:start(dir, {}, function()
                watch_timer:stop()
                watch_timer:start(WATCH_MS, 0, function()
                    vim.schedule(on_listing_change)
                end)
            end)
            watchers[#watchers + 1] = handle
        end
    end
end

---Install mux line visibility and redraw autocmds.
---@return nil
function M.setup()
    apply_visibility()
    watch()

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
