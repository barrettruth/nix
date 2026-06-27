local core = require('mux.core')
local project = require('mux.project')
local view = require('mux.view')

local M = {}

local canon = core.canon
local find_view = core.find_view
local views = core.views
local VIEW_ORDER = core.VIEW_ORDER

---@param group string
---@param text string
---@return string
local function hl(group, text)
    if text == '' then
        return ''
    end
    return ('%%#%s#%s%%*'):format(group, text)
end

---@param current boolean
---@return string
local function label_group(current)
    return current and 'TabLineSel' or 'TabLine'
end

---@param current boolean
---@param last boolean
---@return string
local function mark(current, last)
    if current then
        return '*'
    end
    if last then
        return '-'
    end
    return ''
end

---@param m string
---@param key string
---@param name string
---@param current boolean
---@return string
local function view_segment(m, key, name, current)
    local group = label_group(current)
    return table.concat({
        hl('Directory', m),
        hl(group, key),
        hl('Directory', ':'),
        hl(group, name),
    })
end

---@param m string
---@param name string
---@param current boolean
---@return string
local function session_segment(m, name, current)
    return hl('Directory', m) .. hl(label_group(current), name)
end

---@param entries { cwd: string, socket: string, status: string }[]
---@param current string
---@return string?
local function last_session(entries, current)
    local live = {}
    for _, entry in ipairs(entries) do
        if entry.status == 'live' then
            live[canon(entry.cwd)] = true
        end
    end
    local history = core.state_dir() .. '/history'
    if vim.fn.filereadable(history) ~= 1 then
        return nil
    end
    local lines = vim.fn.readfile(history)
    for i = #lines, 1, -1 do
        local root = canon(lines[i])
        if root ~= '' and root ~= current and live[root] then
            return root
        end
    end
end

---@return string[]
local function view_segments()
    core.prune()
    local current = vim.api.nvim_get_current_tabpage()
    local last = view._alt
    local parts = {}
    for _, name in ipairs(VIEW_ORDER) do
        local tp = find_view(name)
        if tp then
            local spec = views[name]
            parts[#parts + 1] = view_segment(
                mark(tp == current, tp == last),
                spec.key,
                name,
                tp == current
            )
        end
    end
    return parts
end

---@return string[]
local function session_segments()
    local entries = project.list_entries()
    local current = canon(vim.fn.getcwd())
    local last = last_session(entries, current)
    local parts = {}
    for _, entry in ipairs(entries) do
        if entry.status == 'live' then
            local root = canon(entry.cwd)
            local name = vim.fn.fnamemodify(root, ':t')
            if name ~= '' then
                parts[#parts + 1] = session_segment(
                    mark(root == current, root == last),
                    name,
                    root == current
                )
            end
        end
    end
    return parts
end

---@return string
function M.render()
    if vim.env.MUX ~= '1' then
        return ''
    end
    return (' %s%%=%s '):format(
        table.concat(view_segments(), ' '),
        table.concat(session_segments(), ' ')
    )
end

function M.toggle()
    if vim.env.MUX ~= '1' then
        return
    end
    vim.o.showtabline = vim.o.showtabline == 0 and 2 or 0
    pcall(vim.cmd.redrawtabline)
end

return M
