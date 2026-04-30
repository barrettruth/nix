local M = {}

local registry = require('config.completion.forge.registry')
local remote = require('config.completion.forge.remote')

---@param backend string
---@param host string
---@param owner string
---@param repo string
---@return string
local function repo_key(backend, host, owner, repo)
    return backend .. ':' .. host .. ':' .. owner .. '/' .. repo
end

---@param backend config.completion.forge.BackendName
---@param host string
---@param owner string
---@param repo string
---@return config.completion.forge.Repo
local function build(backend, host, owner, repo)
    return {
        backend = backend,
        host = host,
        owner = owner,
        repo = repo,
        key = repo_key(backend, host, owner, repo),
    }
end

---@param bufnr integer
---@return config.completion.forge.Repo?
local function from_forge_buf(bufnr)
    local ok, scope = pcall(function()
        return vim.b[bufnr].forge_scope
    end)
    if ok and type(scope) == 'table' and type(scope.host) == 'string' then
        local owner = scope.owner
        local repo = scope.repo
        if not owner or not repo then
            local slug = scope.slug or ''
            owner, repo = slug:match('^([^/]+)/(.+)$')
        end
        if owner and repo and owner ~= '' and repo ~= '' then
            local backend = registry.backend_for_host(scope.host)
            if backend then
                return build(backend, scope.host, owner, repo)
            end
        end
    end

    local ok2, public = pcall(function()
        return vim.b[bufnr].forge
    end)
    if ok2 and type(public) == 'table' and type(public.url) == 'string' then
        local host, owner, repo = remote.parse(public.url)
        if host and owner and repo then
            local backend = registry.backend_for_host(host)
            if backend then
                return build(backend, host, owner, repo)
            end
        end
    end

    return nil
end

---@param bufnr integer
---@return string
local function buffer_dir(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' then
        return vim.uv.cwd() or '.'
    end
    return vim.fn.fnamemodify(name, ':p:h')
end

---@param bufnr integer
---@return config.completion.forge.Repo?
local function from_remotes(bufnr)
    local _, remotes = remote.collect(buffer_dir(bufnr))
    if not next(remotes) then
        return nil
    end

    local order = remote.priority_order(remotes)
    for _, name in ipairs(order) do
        local host, owner, repo = remote.parse(remotes[name])
        if host and owner and repo then
            local backend = registry.backend_for_host(host)
            if backend then
                return build(backend, host, owner, repo)
            end
        end
    end

    return nil
end

---@param bufnr integer
---@return config.completion.forge.Repo?
function M.derive(bufnr)
    bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()

    local repo = from_forge_buf(bufnr)
    if repo then
        return repo
    end

    return from_remotes(bufnr)
end

---@param bufnr integer
---@param owner string
---@param repo string
---@return config.completion.forge.Repo?
function M.cross_repo(bufnr, owner, repo)
    local base = M.derive(bufnr)
    if not base then
        return nil
    end
    return build(base.backend, base.host, owner, repo)
end

return M
