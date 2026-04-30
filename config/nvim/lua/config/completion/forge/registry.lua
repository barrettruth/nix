local M = {}

---@type table<string, config.completion.forge.Backend>
local backends = {}

---@type config.completion.forge.Backend[]
local order = {}

---@param backend config.completion.forge.Backend
function M.register(backend)
    if backends[backend.name] then
        return
    end
    if backend.cli and vim.fn.executable(backend.cli) ~= 1 then
        return
    end
    backends[backend.name] = backend
    order[#order + 1] = backend
end

---@param name string
---@return config.completion.forge.Backend?
function M.get(name)
    return backends[name]
end

---@param host string
---@return config.completion.forge.BackendName?
function M.backend_for_host(host)
    if host == '' then
        return nil
    end
    for _, backend in ipairs(order) do
        for _, h in ipairs(backend.hosts or {}) do
            if h == host then
                return backend.name
            end
        end
        if backend.matches_host and backend.matches_host(host) then
            return backend.name
        end
    end
    return nil
end

---@return config.completion.forge.Backend[]
function M.all()
    return order
end

local registered = false
local function ensure_registered()
    if registered then
        return
    end
    registered = true
    M.register(require('config.completion.forge.github'))
    M.register(require('config.completion.forge.gitlab'))
    M.register(require('config.completion.forge.gitea'))
end

ensure_registered()

return M
