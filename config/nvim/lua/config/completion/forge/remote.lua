local M = {}

local util = require('config.completion.util')

local PRIORITY = { 'forgejo', 'upstream', 'origin' }

---@param url string
---@return string? host
---@return string? owner
---@return string? repo
local function parse_url(url)
    if url == '' then
        return nil
    end

    local stripped = url:gsub('%.git$', '')

    local host, path = stripped:match('^ssh://[^@]+@([^/]+)/(.+)$')
    if not host then
        host, path = stripped:match('^[^@]+@([^:]+):(.+)$')
    end
    if not host then
        host, path = stripped:match('^https?://([^/]+)/(.+)$')
    end
    if not host or not path then
        return nil
    end

    local owner, repo = path:match('^([^/]+)/([^/]+)$')
    if not owner or not repo then
        return nil
    end

    return host, owner, repo
end

---@param dir string
---@return string
local function git_root(dir)
    if dir == '' then
        dir = vim.uv.cwd() or '.'
    end
    local out = vim.trim(
        util.system_text({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' })
    )
    if out == '' and dir:match('/%.git$') then
        out = vim.fn.fnamemodify(dir, ':h')
    end
    if out == '' then
        out = vim.trim(util.system_text({
            'git',
            '-C',
            vim.uv.cwd() or '.',
            'rev-parse',
            '--show-toplevel',
        }))
    end
    return out
end

---@param dir string
---@return table<string, string>
local function list_remotes(dir)
    local remotes = {}
    if dir == '' then
        return remotes
    end

    local out = util.system_text({ 'git', '-C', dir, 'remote', '-v' })
    for line in (out .. '\n'):gmatch('(.-)\n') do
        local name, url = line:match('^(%S+)%s+(%S+)%s+%(fetch%)$')
        if name and url and not remotes[name] then
            remotes[name] = url
        end
    end
    return remotes
end

---@param dir string
---@return string root
---@return table<string, string> remotes
function M.collect(dir)
    local root = git_root(dir)
    if root == '' then
        return '', {}
    end
    return root, list_remotes(root)
end

---@param remotes table<string, string>
---@return string[]
function M.priority_order(remotes)
    local seen = {}
    local order = {}

    for _, name in ipairs(PRIORITY) do
        if remotes[name] then
            order[#order + 1] = name
            seen[name] = true
        end
    end

    local extras = {}
    for name in pairs(remotes) do
        if not seen[name] then
            extras[#extras + 1] = name
        end
    end
    table.sort(extras)

    for _, name in ipairs(extras) do
        order[#order + 1] = name
    end

    return order
end

---@param url string
---@return string? host
---@return string? owner
---@return string? repo
function M.parse(url)
    return parse_url(url)
end

return M
