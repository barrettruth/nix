local M = {
    name = 'gitlab',
    cli = 'glab',
    hosts = { 'gitlab.com' },
    triggers = { '#', '!', '@' },
    bucket_for_trigger = {
        ['#'] = 'refs',
        ['!'] = 'mrs',
        ['@'] = 'mentions',
    },
}

local api = require('config.completion.forge.api')

local TIMEOUT_LIST = 6000
local TIMEOUT_EXACT = 3000

---Encode the GitLab project path. `glab api projects/...` accepts the
---URL-encoded full project path; nested groups become `%2F`-separated.
---@param repo config.completion.forge.Repo
---@return string
local function project_path(repo)
    local slug = repo.owner .. '/' .. repo.repo
    return (slug:gsub('/', '%%2F'))
end

---@param state? string
---@return 'open'|'closed'|'merged'
local function normalize_state(state)
    if state == 'merged' then
        return 'merged'
    end
    if state == 'closed' or state == 'locked' then
        return 'closed'
    end
    return 'open'
end

---@param node table
---@param kind config.completion.forge.RefKind
---@return config.completion.forge.RefItem
local function format_ref(node, kind)
    return {
        kind = kind,
        number = node.iid,
        title = node.title or '',
        state = normalize_state(node.state),
        updated = api.parse_iso8601(node.updated_at),
        url = node.web_url,
        draft = (node.draft and true)
            or (node.work_in_progress and true)
            or false,
    }
end

---@param repo config.completion.forge.Repo
---@param scope 'issues'|'merge_requests'
---@param kind config.completion.forge.RefKind
---@param cb fun(items: config.completion.forge.RefItem[]?, err: string?)
local function fetch_list(repo, scope, kind, cb)
    local path = ('projects/%s/%s?state=all&per_page=100&order_by=updated_at'):format(
        project_path(repo),
        scope
    )
    vim.system(
        { 'glab', 'api', path },
        { text = true, timeout = TIMEOUT_LIST },
        function(result)
            local err = api.classify_error(result)
            if err then
                api.warn(
                    repo,
                    err,
                    ('forge: glab %s failed (%s) for %s'):format(
                        scope,
                        err,
                        repo.key
                    )
                )
                vim.schedule(function()
                    cb(nil, err)
                end)
                return
            end
            local data, derr = api.decode_json(result)
            if not data then
                api.warn(
                    repo,
                    'decode',
                    ('forge: glab %s returned invalid JSON'):format(scope)
                )
                vim.schedule(function()
                    cb(nil, derr)
                end)
                return
            end
            local items = {}
            for _, n in ipairs(data) do
                items[#items + 1] = format_ref(n, kind)
            end
            table.sort(items, function(a, b)
                return (a.updated or 0) > (b.updated or 0)
            end)
            vim.schedule(function()
                cb(items, nil)
            end)
        end
    )
end

---@param repo config.completion.forge.Repo
---@param cb fun(items: config.completion.forge.MentionItem[]?, err: string?)
local function fetch_mentions(repo, cb)
    local path = ('projects/%s/users?per_page=100'):format(project_path(repo))
    vim.system(
        { 'glab', 'api', path },
        { text = true, timeout = TIMEOUT_LIST },
        function(result)
            local err = api.classify_error(result)
            if err then
                api.warn(
                    repo,
                    err,
                    ('forge: glab users failed (%s) for %s'):format(
                        err,
                        repo.key
                    )
                )
                vim.schedule(function()
                    cb(nil, err)
                end)
                return
            end
            local data, derr = api.decode_json(result)
            if not data then
                api.warn(
                    repo,
                    'decode',
                    'forge: glab users returned invalid JSON'
                )
                vim.schedule(function()
                    cb(nil, derr)
                end)
                return
            end
            local seen = {}
            local items = {}
            for _, u in ipairs(data) do
                if
                    u.username
                    and not seen[u.username]
                    and not api.is_bot_login(u.username)
                then
                    seen[u.username] = true
                    items[#items + 1] = {
                        login = u.username,
                        name = u.name,
                        source = 'project_user',
                    }
                end
            end
            vim.schedule(function()
                cb(items, nil)
            end)
        end
    )
end

---@param repo config.completion.forge.Repo
---@param scope 'issues'|'merge_requests'
---@param kind config.completion.forge.RefKind
---@param n integer
---@param cb fun(item: config.completion.forge.RefItem?, err: string?)
local function fetch_exact(repo, scope, kind, n, cb)
    local path = ('projects/%s/%s/%d'):format(project_path(repo), scope, n)
    vim.system(
        { 'glab', 'api', path },
        { text = true, timeout = TIMEOUT_EXACT },
        function(result)
            local err = api.classify_error(result)
            if err then
                vim.schedule(function()
                    cb(nil, err)
                end)
                return
            end
            local data, derr = api.decode_json(result)
            if not data then
                vim.schedule(function()
                    cb(nil, derr)
                end)
                return
            end
            vim.schedule(function()
                cb(format_ref(data, kind), nil)
            end)
        end
    )
end

---@param repo config.completion.forge.Repo
---@param scope 'issues'|'merge_requests'
---@param n integer
---@param cb fun(body: string?, err: string?)
local function fetch_doc(repo, scope, n, cb)
    local path = ('projects/%s/%s/%d'):format(project_path(repo), scope, n)
    vim.system(
        { 'glab', 'api', path },
        { text = true, timeout = TIMEOUT_EXACT },
        function(result)
            local err = api.classify_error(result)
            if err then
                vim.schedule(function()
                    cb(nil, err)
                end)
                return
            end
            local data, derr = api.decode_json(result)
            if not data then
                vim.schedule(function()
                    cb(nil, derr)
                end)
                return
            end
            local body = (data.description or '')
                :gsub('\r\n', '\n')
                :gsub('%s+$', '')
            vim.schedule(function()
                cb(body, nil)
            end)
        end
    )
end

---@param bucket string
---@param repo config.completion.forge.Repo
---@param cb fun(items: any?, err: string?)
function M.fetch(bucket, repo, cb)
    if bucket == 'refs' then
        return fetch_list(repo, 'issues', 'issue', cb)
    end
    if bucket == 'mrs' then
        return fetch_list(repo, 'merge_requests', 'mr', cb)
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
        return fetch_exact(repo, 'issues', 'issue', n, cb)
    end
    if bucket == 'mrs' then
        return fetch_exact(repo, 'merge_requests', 'mr', n, cb)
    end
    cb(nil, 'unsupported_bucket')
end

---@param bucket string
---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(body: string?, err: string?)
function M.fetch_doc(bucket, repo, n, cb)
    if bucket == 'refs' then
        return fetch_doc(repo, 'issues', n, cb)
    end
    if bucket == 'mrs' then
        return fetch_doc(repo, 'merge_requests', n, cb)
    end
    cb(nil, 'unsupported_bucket')
end

return M
