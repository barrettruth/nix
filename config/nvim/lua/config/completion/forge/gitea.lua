local M = {
    name = 'gitea',
    cli = 'tea',
    hosts = {},
    triggers = { '#', '@' },
    bucket_for_trigger = {
        ['#'] = 'refs',
        ['@'] = 'mentions',
    },
}

local api = require('config.completion.forge.api')

local TIMEOUT_LIST = 6000
local TIMEOUT_EXACT = 3000
local TIMEOUT_LOGINS = 1000

---@class config.completion.forge.gitea.Login
---@field name string
---@field url_host string
---@field ssh_host string

---@type config.completion.forge.gitea.Login[]?
local logins_cache

---Load configured tea logins once per session. Synchronous because callers
---(`matches_host`, `login_for_host`) run in the omnifunc/aggregator hot
---path and need a definitive answer before forge_refs can dispatch. Cost
---is a single ~50ms shell-out to read a local config file.
---@return config.completion.forge.gitea.Login[]
local function load_logins()
    local result = vim.system(
        { 'tea', 'logins', 'list', '-o', 'json' },
        { text = true, timeout = TIMEOUT_LOGINS }
    ):wait()
    if result.code ~= 0 then
        return {}
    end
    local stdout = result.stdout or ''
    if stdout == '' then
        return {}
    end
    local ok, data = pcall(vim.json.decode, stdout)
    if not ok or type(data) ~= 'table' then
        return {}
    end
    local out = {}
    for _, l in ipairs(data) do
        local url_host
        if type(l.url) == 'string' then
            url_host = l.url:match('^https?://([^/]+)')
        end
        out[#out + 1] = {
            name = l.name or '',
            url_host = url_host or '',
            ssh_host = l.ssh_host or '',
        }
    end
    return out
end

---@return config.completion.forge.gitea.Login[]
local function ensure_logins()
    if logins_cache == nil then
        logins_cache = load_logins()
    end
    return logins_cache
end

---@param host string
---@return string? login_name
local function login_for_host(host)
    if host == '' then
        return nil
    end
    for _, l in ipairs(ensure_logins()) do
        if l.url_host == host or l.ssh_host == host then
            return l.name
        end
    end
    return nil
end

---@param host string
---@return boolean
function M.matches_host(host)
    return login_for_host(host) ~= nil
end

---@param data table
---@return table?
local function pr_block(data)
    local pr = data.pull_request
    if type(pr) == 'table' then
        return pr
    end
    return nil
end

---@param state? string
---@param data table
---@return 'open'|'closed'|'merged'
local function normalize_state(state, data)
    local pr = pr_block(data)
    if pr and pr.merged then
        return 'merged'
    end
    if state == 'closed' then
        return 'closed'
    end
    return 'open'
end

---@param data table
---@return config.completion.forge.RefItem
local function format_ref(data)
    local pr = pr_block(data)
    local kind = pr and 'pr' or 'issue'
    local url = data.html_url
    if
        kind == 'pr'
        and pr
        and type(pr.html_url) == 'string'
        and pr.html_url ~= ''
    then
        url = pr.html_url
    end
    return {
        kind = kind,
        number = data.number,
        title = data.title or '',
        state = normalize_state(data.state, data),
        updated = api.parse_iso8601(data.updated_at),
        url = url,
        draft = (pr and pr.draft) and true or false,
    }
end

---@param login string
---@param path string
---@param timeout integer
---@param on_result fun(data: any?, err: string?)
local function call_api(login, path, timeout, on_result)
    vim.system(
        { 'tea', 'api', '-l', login, path },
        { text = true, timeout = timeout },
        function(result)
            local err = api.classify_error(result)
            if err then
                vim.schedule(function()
                    on_result(nil, err)
                end)
                return
            end
            local data, derr = api.decode_json(result)
            if not data then
                vim.schedule(function()
                    on_result(nil, derr)
                end)
                return
            end
            vim.schedule(function()
                on_result(data, nil)
            end)
        end
    )
end

---@param repo config.completion.forge.Repo
---@return string? login
---@return string? err
local function login_or_err(repo)
    local login = login_for_host(repo.host)
    if not login then
        return nil, 'no_auth'
    end
    return login, nil
end

---@param repo config.completion.forge.Repo
---@param cb fun(items: config.completion.forge.RefItem[]?, err: string?)
local function fetch_refs(repo, cb)
    local login, lerr = login_or_err(repo)
    if not login then
        api.warn(
            repo,
            'no_auth',
            ('forge: no tea login configured for %s'):format(repo.host)
        )
        cb(nil, lerr)
        return
    end
    local path = ('repos/%s/%s/issues?state=open&type=all&limit=50'):format(
        repo.owner,
        repo.repo
    )
    call_api(login, path, TIMEOUT_LIST, function(data, err)
        if err then
            api.warn(
                repo,
                err,
                ('forge: tea issues failed (%s) for %s'):format(err, repo.key)
            )
            cb(nil, err)
            return
        end
        local items = {}
        for _, n in ipairs(data) do
            items[#items + 1] = format_ref(n)
        end
        table.sort(items, function(a, b)
            return (a.updated or 0) > (b.updated or 0)
        end)
        cb(items, nil)
    end)
end

---@param repo config.completion.forge.Repo
---@param cb fun(items: config.completion.forge.MentionItem[]?, err: string?)
local function fetch_mentions(repo, cb)
    local login, lerr = login_or_err(repo)
    if not login then
        api.warn(
            repo,
            'no_auth',
            ('forge: no tea login configured for %s'):format(repo.host)
        )
        cb(nil, lerr)
        return
    end

    local results = { assignees = nil, collaborators = nil }
    local errors = {}
    local pending = 2

    local function settle()
        pending = pending - 1
        if pending > 0 then
            return
        end
        if not results.assignees and not results.collaborators then
            api.warn(
                repo,
                'unavailable',
                ('forge: tea mention fetch failed for %s'):format(repo.key)
            )
            cb(nil, errors[1] or 'unavailable')
            return
        end
        local seen = {}
        local items = {}
        for _, a in ipairs(results.assignees or {}) do
            if
                a.login
                and not seen[a.login]
                and not api.is_bot_login(a.login)
            then
                seen[a.login] = true
                items[#items + 1] = {
                    login = a.login,
                    name = a.full_name,
                    source = 'assignee',
                }
            end
        end
        for _, c in ipairs(results.collaborators or {}) do
            if
                c.login
                and not seen[c.login]
                and not api.is_bot_login(c.login)
            then
                seen[c.login] = true
                items[#items + 1] = {
                    login = c.login,
                    name = c.full_name,
                    source = 'collaborator',
                }
            end
        end
        cb(items, nil)
    end

    local function fetch(path, key)
        call_api(login, path, TIMEOUT_LIST, function(data, err)
            if err then
                errors[#errors + 1] = err
                settle()
                return
            end
            results[key] = data
            settle()
        end)
    end

    fetch(('repos/%s/%s/assignees'):format(repo.owner, repo.repo), 'assignees')
    fetch(
        ('repos/%s/%s/collaborators'):format(repo.owner, repo.repo),
        'collaborators'
    )
end

---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(item: config.completion.forge.RefItem?, err: string?)
local function fetch_exact(repo, n, cb)
    local login, lerr = login_or_err(repo)
    if not login then
        cb(nil, lerr)
        return
    end
    local path = ('repos/%s/%s/issues/%d'):format(repo.owner, repo.repo, n)
    call_api(login, path, TIMEOUT_EXACT, function(data, err)
        if err then
            cb(nil, err)
            return
        end
        cb(format_ref(data), nil)
    end)
end

---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(body: string?, err: string?)
local function fetch_doc(repo, n, cb)
    local login, lerr = login_or_err(repo)
    if not login then
        cb(nil, lerr)
        return
    end
    local path = ('repos/%s/%s/issues/%d'):format(repo.owner, repo.repo, n)
    call_api(login, path, TIMEOUT_EXACT, function(data, err)
        if err then
            cb(nil, err)
            return
        end
        local body = (data.body or ''):gsub('\r\n', '\n'):gsub('%s+$', '')
        cb(body, nil)
    end)
end

---@param bucket string
---@param repo config.completion.forge.Repo
---@param cb fun(items: any?, err: string?)
function M.fetch(bucket, repo, cb)
    if bucket == 'refs' then
        return fetch_refs(repo, cb)
    end
    if bucket == 'mentions' then
        return fetch_mentions(repo, cb)
    end
    cb(nil, 'unsupported_bucket')
end

---@param bucket string
---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(item: any?, err: string?)
function M.fetch_exact(bucket, repo, n, cb)
    if bucket == 'refs' then
        return fetch_exact(repo, n, cb)
    end
    cb(nil, 'unsupported_bucket')
end

---@param bucket string
---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(body: string?, err: string?)
function M.fetch_doc(bucket, repo, n, cb)
    if bucket == 'refs' then
        return fetch_doc(repo, n, cb)
    end
    cb(nil, 'unsupported_bucket')
end

return M
