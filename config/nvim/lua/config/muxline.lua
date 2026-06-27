local M = {}

local function hl(group, text)
    if text == '' then
        return ''
    end
    return ('%%#%s#%s%%*'):format(group, text)
end

local function segment(mark, key, name, current)
    local group = current and 'TabLineSel' or 'TabLine'
    return table.concat({
        hl('Directory', mark),
        hl(group, key),
        hl('Directory', ':'),
        hl(group, name),
    })
end

local function session_segment(mark, name, current)
    local group = current and 'TabLineSel' or 'TabLine'
    return hl('Directory', mark) .. hl(group, name)
end

local function last_view(core)
    local ok, view = pcall(require, 'mux.view')
    local tp = ok and view._alt
    return tp and core.tab_view[tp] or nil
end

local function last_session(core, entries, current)
    local live = {}
    for _, entry in ipairs(entries) do
        if entry.status == 'live' then
            live[core.canon(entry.cwd)] = true
        end
    end
    local history = core.state_dir() .. '/history'
    if vim.fn.filereadable(history) ~= 1 then
        return nil
    end
    local lines = vim.fn.readfile(history)
    for i = #lines, 1, -1 do
        local root = core.canon(lines[i])
        if root ~= '' and root ~= current and live[root] then
            return root
        end
    end
end

local function view_segments(core)
    core.prune()
    local current = vim.api.nvim_get_current_tabpage()
    local last = last_view(core)
    local parts = {}
    for _, name in ipairs(core.VIEW_ORDER) do
        local tp = core.find_view(name)
        if tp then
            local spec = core.views[name]
            local mark = tp == current and '*' or (tp == last and '-' or '')
            parts[#parts + 1] = segment(mark, spec.key, name, tp == current)
        end
    end
    return parts
end

local function session_segments(core)
    local ok, project = pcall(require, 'mux.project')
    if not ok then
        return {}
    end
    local entries = project.list_entries()
    local current = core.canon(vim.fn.getcwd())
    local last = last_session(core, entries, current)
    local parts = {}
    for _, entry in ipairs(entries) do
        if entry.status == 'live' then
            local root = core.canon(entry.cwd)
            local mark = root == current and '*' or (root == last and '-' or '')
            local name = vim.fn.fnamemodify(root, ':t')
            if name ~= '' then
                parts[#parts + 1] = session_segment(mark, name, root == current)
            end
        end
    end
    return parts
end

function M.render()
    if vim.env.MUX ~= '1' then
        return ''
    end
    local ok, core = pcall(require, 'mux.core')
    if not ok then
        return ''
    end
    return (' %s%%=%s '):format(
        table.concat(view_segments(core), '  '),
        table.concat(session_segments(core), '  ')
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
