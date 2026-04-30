local M = {}

local notify = require('config.completion.forge.notify')

---@param result vim.SystemCompleted
---@return string?
function M.classify_error(result)
    if result.code == 124 then
        return 'timeout'
    end
    local stderr = result.stderr or ''
    if
        stderr:find('not logged into', 1, true)
        or stderr:find('authentication required', 1, true)
        or stderr:find('HTTP 401', 1, true)
        or stderr:find('401 Unauthorized', 1, true)
    then
        return 'no_auth'
    end
    if result.code ~= 0 then
        return 'unavailable'
    end
    return nil
end

---@param result vim.SystemCompleted
---@return any?
---@return string?
function M.decode_json(result)
    local stdout = result.stdout or ''
    if stdout == '' then
        return nil, 'empty'
    end
    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok then
        return nil, 'decode'
    end
    return decoded, nil
end

---@param ts? string
---@return integer?
function M.parse_iso8601(ts)
    if type(ts) ~= 'string' or ts == '' then
        return nil
    end
    local y, mo, d, h, mi, s = ts:match('^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
    if not y then
        return nil
    end
    return os.time({
        year = tonumber(y),
        month = tonumber(mo),
        day = tonumber(d),
        hour = tonumber(h),
        min = tonumber(mi),
        sec = tonumber(s),
    })
end

---@param repo config.completion.forge.Repo
---@param reason string
---@param msg string
function M.warn(repo, reason, msg)
    notify.warn(repo.key, reason, msg)
end

---Conservative bot heuristic for backends without an explicit Bot account
---type. Prefer false negatives (let some bots through) over false positives
---(filtering humans).
---@param login string
---@return boolean
function M.is_bot_login(login)
    if not login or login == '' then
        return false
    end
    local l = login:lower()
    if l:find('%[bot%]') or l:find('_bot$') or l:find('%-bot$') then
        return true
    end
    if
        l == 'renovate'
        or l == 'dependabot'
        or l == 'release-manager'
        or l == 'gitlab-bot'
    then
        return true
    end
    return false
end

return M
