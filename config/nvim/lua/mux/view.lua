local core = require('mux.core')

local views = core.views
local tab_view = core.tab_view
local tag = core.tag
local find_view = core.find_view

local M = {}

-- cwd -> set of justfile recipe names (cleared on DirChanged).
local recipe_cache = {}

function M.reset_recipes()
    recipe_cache = {}
end

-- Whether `cwd`'s justfile defines `recipe`, caching `just --summary` per cwd.
---@param cwd string
---@param recipe string
---@return boolean
local function has_recipe(cwd, recipe)
    local set = recipe_cache[cwd]
    if not set then
        set = {}
        local res = vim.system(
            { 'just', '--summary' },
            { text = true, cwd = cwd }
        )
            :wait()
        if res.code == 0 and res.stdout then
            for r in res.stdout:gmatch('%S+') do
                set[r] = true
            end
        end
        recipe_cache[cwd] = set
    end
    return set[recipe] == true
end

---@param tp integer
function M.close_view_tab(tp)
    vim.schedule(function()
        if not vim.api.nvim_tabpage_is_valid(tp) then
            return
        end
        if #vim.api.nvim_list_tabpages() <= 1 then
            -- Hop to the most-recently-used live project
            -- TODO: check this Reset this lone tab to a clean edit view first so the server
            -- we leave behind isn't holding a dead terminal;
            -- last_session() :detaches only when nothing else is live.
            local win = vim.api.nvim_tabpage_get_win(tp)
            vim.api.nvim_win_call(win, function()
                pcall(vim.cmd, 'enew')
            end)
            tab_view[tp] = 'edit'
            require('mux.project').last_session()
            return
        end
        local win = vim.api.nvim_tabpage_get_win(tp)
        vim.api.nvim_win_call(win, function()
            pcall(vim.cmd, 'tabclose')
        end)
        tab_view[tp] = nil
    end)
end

---@param name string
---@param restoring boolean true when re-opening from a saved session
function M.materialize(name, restoring)
    local spec = views[name]
    local cwd = vim.fn.getcwd()
    if spec.kind == 'editor' then
        vim.cmd.edit(cwd)
    elseif spec.kind == 'vcs' then
        pcall(vim.cmd, 'Git|only')
    elseif spec.kind == 'terminal' or spec.kind == 'task' then
        local cmd = (restoring and spec.restore_cmd)
            or spec.cmd
            or { 'just', spec.recipe }
        vim.fn.jobstart(cmd, { term = true, cwd = cwd })
        vim.cmd.startinsert()
    end
end

---@param name string
function M.open_view(name)
    local spec = views[name]
    if not spec then
        return
    end
    local existing = find_view(name)
    if existing then
        vim.api.nvim_set_current_tabpage(existing)
        return
    end

    local cwd = vim.fn.getcwd()
    if spec.kind == 'task' and not has_recipe(cwd, spec.recipe) then
        vim.notify(
            ('mux: no "%s" recipe in justfile'):format(spec.recipe),
            vim.log.levels.WARN
        )
        return
    end

    vim.cmd.tabnew()
    tag(vim.api.nvim_get_current_tabpage(), name)
    M.materialize(name, false)
end

---@param spec string|{ view?: string, win?: integer, tab?: integer, create?: boolean }
---@return integer? win
---@return integer|string tp
function M.resolve_view(spec)
    if type(spec) == 'string' then
        spec = { view = spec }
    end
    spec = spec or {}

    if spec.win ~= nil then
        local win = tonumber(spec.win)
        if not (win and vim.api.nvim_win_is_valid(win)) then
            return nil, 'invalid window: ' .. tostring(spec.win)
        end
        return win, vim.api.nvim_win_get_tabpage(win)
    end

    if spec.tab ~= nil then
        local tp = vim.api.nvim_list_tabpages()[tonumber(spec.tab) or -1]
        if not (tp and vim.api.nvim_tabpage_is_valid(tp)) then
            return nil, 'invalid tab: ' .. tostring(spec.tab)
        end
        return vim.api.nvim_tabpage_get_win(tp), tp
    end

    local name = spec.view
    if not name then
        return nil, 'resolve_view: need view, win, or tab'
    end
    if not views[name] then
        return nil, 'unknown view: ' .. tostring(name)
    end
    local tp = find_view(name)
    if not tp then
        if spec.create == false then
            return nil, 'view not open: ' .. name
        end
        local cur = vim.api.nvim_get_current_tabpage()
        local saved_alt = M._alt
        vim.cmd.tabnew()
        tp = vim.api.nvim_get_current_tabpage()
        tag(tp, name)
        M.materialize(name, false)
        if vim.api.nvim_tabpage_is_valid(cur) then
            vim.api.nvim_set_current_tabpage(cur)
        end
        M._alt = saved_alt
    end
    return vim.api.nvim_tabpage_get_win(tp), tp
end

---@param spec string|table
---@param fn fun(): any
---@return any result, string? err
function M.in_view(spec, fn)
    local win, tp = M.resolve_view(spec)
    if not win then
        return nil, tp
    end
    return vim.api.nvim_win_call(win, fn), nil
end

function M.state()
    local cur = vim.api.nvim_get_current_tabpage()
    local tabs = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local win = vim.api.nvim_tabpage_get_win(tp)
        local buf = vim.api.nvim_win_get_buf(win)
        tabs[#tabs + 1] = {
            tab = vim.api.nvim_tabpage_get_number(tp),
            view = tab_view[tp],
            win = win,
            current = tp == cur,
            buftype = vim.bo[buf].buftype,
            filetype = vim.bo[buf].filetype,
        }
    end
    return { current_view = tab_view[cur], tabs = tabs }
end

return M
