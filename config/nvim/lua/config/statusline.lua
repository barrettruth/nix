local M = {}

local forge
local forge_loaded = false

local function load_forge()
    if forge_loaded then
        return forge
    end
    forge_loaded = true
    pcall(require('config.lz').load, 'barrettruth/forge.nvim')
    local ok, mod = pcall(function()
        return require('forge')
    end)
    if ok then
        forge = mod
    end
    return forge
end

-- "[branch #pr] " (or "[branch] "), leveraging forge.nvim
local function forge_prefix()
    local mod = load_forge()
    if not mod then
        return ''
    end
    local status = mod.status()
    if not status then
        return ''
    end
    local pr = status.pr
    if pr then
        return ('[%s #%s] '):format(status.branch, pr.num)
    end
    return ('[%s] '):format(status.branch)
end

-- " [project]" when inside a mux server
local function mux_suffix()
    if vim.env.MUX ~= '1' then
        return ''
    end
    local session = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
    if session == '' then
        return ''
    end
    local ok, core = pcall(require, 'mux.core')
    local view = ok and core.tab_view[vim.api.nvim_get_current_tabpage()]
    if view then
        return (' [%s:%s]'):format(session, view)
    end
    return (' [%s]'):format(session)
end

function M.render()
    local name = vim.fn.expand('%')
    local path = name ~= '' and ('%s '):format(vim.fn.expand('%:~')) or ''
    local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or vim.bo.buftype
    return (' %s%s%%h%%m%%r%%=%%c:%%l/%%L %s%s '):format(
        forge_prefix(),
        path,
        filetype,
        mux_suffix()
    )
end

return M
