local M = {}

local THROTTLE_MS = 60 * 1000

---@type table<string, true>
local explicit = {}

---@type table<string, integer>
local last_emit = {}

---@param repo_key string
function M.note_explicit_attempt(repo_key)
    if repo_key == '' then
        return
    end
    explicit[repo_key] = true
end

---@param repo_key string
---@param reason string
---@param msg string
function M.warn(repo_key, reason, msg)
    if not explicit[repo_key] then
        return
    end

    local key = repo_key .. ':' .. reason
    local now = vim.uv.now()
    local prev = last_emit[key]
    if prev and now - prev < THROTTLE_MS then
        return
    end

    last_emit[key] = now
    vim.schedule(function()
        vim.notify(msg, vim.log.levels.WARN)
    end)
end

return M
