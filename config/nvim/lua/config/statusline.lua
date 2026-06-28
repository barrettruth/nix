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

---@param scope? forge.Scope
---@return string?
local function scope_name(scope)
    if not scope then
        return nil
    end
    local owner = scope.owner or scope.namespace
    if owner and scope.repo then
        return owner .. '/' .. scope.repo
    end
    if scope.slug then
        local org, repo = scope.slug:match('^([^/]+)/(.+)$')
        if org and repo then
            return org .. '/' .. repo
        end
    end
end

---@param pr forge.PRRef
---@param scope? forge.Scope
---@return string
local function pr_name(pr, scope)
    local repo = scope_name(pr.scope or scope)
    if repo then
        return repo .. '#' .. pr.num
    end
    return '#' .. pr.num
end

-- "branch owner/repo#pr " (or "branch "), leveraging forge.nvim
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
        return ('%%#Comment#%s%%* %%#Comment#%s%%* '):format(
            status.branch,
            pr_name(pr, status.scope)
        )
    end
    return ('%%#Comment#%s%%* '):format(status.branch)
end

function M.render()
    local name = vim.fn.expand('%')
    local path = name ~= ''
            and ('%%#Directory#%s%%* '):format(vim.fn.expand('%:~'))
        or ''
    local buftype = vim.bo.buftype
    local flags = buftype == 'terminal' and '%h%r' or '%h%m%r'
    local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or buftype
    return (' %s%s%s%%=%%c:%%l/%%L %s '):format(
        path,
        forge_prefix(),
        flags,
        filetype
    )
end

return M
