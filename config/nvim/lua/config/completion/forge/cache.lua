local M = {}

---@class config.completion.forge.cache.Bucket
---@field state 'idle'|'loading'|'ready'|'error'
---@field items? any
---@field err? string
---@field ts? integer
---@field waiters? fun(items: any?, err: string?)[]

---@type table<string, table<string, config.completion.forge.cache.Bucket>>
local store = {}

---@param repo_key string
---@param bucket string
---@return config.completion.forge.cache.Bucket
local function ensure(repo_key, bucket)
    store[repo_key] = store[repo_key] or {}
    store[repo_key][bucket] = store[repo_key][bucket] or { state = 'idle' }
    return store[repo_key][bucket]
end

---@param repo_key string
---@param bucket string
---@return config.completion.forge.cache.Bucket?
function M.get(repo_key, bucket)
    return store[repo_key] and store[repo_key][bucket] or nil
end

---@param repo_key string
---@param bucket string
---@return boolean
function M.is_loading(repo_key, bucket)
    local b = M.get(repo_key, bucket)
    return b ~= nil and b.state == 'loading'
end

---@param repo_key string
---@param bucket string
---@return boolean
function M.is_ready(repo_key, bucket)
    local b = M.get(repo_key, bucket)
    return b ~= nil and b.state == 'ready'
end

---@param repo_key string
---@param bucket string
---@param waiter? fun(items: any?, err: string?)
function M.mark_loading(repo_key, bucket, waiter)
    local b = ensure(repo_key, bucket)
    b.state = 'loading'
    b.items = nil
    b.err = nil
    if waiter then
        b.waiters = b.waiters or {}
        b.waiters[#b.waiters + 1] = waiter
    end
end

---@param repo_key string
---@param bucket string
---@param waiter fun(items: any?, err: string?)
function M.add_waiter(repo_key, bucket, waiter)
    local b = ensure(repo_key, bucket)
    b.waiters = b.waiters or {}
    b.waiters[#b.waiters + 1] = waiter
end

---@param repo_key string
---@param bucket string
---@param items any
function M.set_ready(repo_key, bucket, items)
    local b = ensure(repo_key, bucket)
    b.state = 'ready'
    b.items = items
    b.err = nil
    b.ts = vim.uv.now()
    local waiters = b.waiters or {}
    b.waiters = nil
    for _, w in ipairs(waiters) do
        pcall(w, items, nil)
    end
end

---@param repo_key string
---@param bucket string
---@param err string
function M.set_error(repo_key, bucket, err)
    local b = ensure(repo_key, bucket)
    b.state = 'error'
    b.items = nil
    b.err = err
    b.ts = vim.uv.now()
    local waiters = b.waiters or {}
    b.waiters = nil
    for _, w in ipairs(waiters) do
        pcall(w, nil, err)
    end
end

return M
