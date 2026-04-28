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

function M.render()
    local name = vim.fn.expand('%')
    local path = name ~= '' and ('%s '):format(vim.fn.expand('%:~')) or ''
    local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or vim.bo.buftype
    return (' %s%s%%h%%m%%r%%=%%c:%%l/%%L %s '):format(
        forge_prefix(),
        path,
        filetype
    )
end

return M
