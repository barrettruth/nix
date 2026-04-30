local M = {
    name = 'github',
    cli = 'gh',
    hosts = { 'github.com' },
    triggers = { '#', '@' },
    bucket_for_trigger = {
        ['#'] = 'refs',
        ['@'] = 'mentions',
    },
}

local api = require('config.completion.forge.api')

local TIMEOUT_LIST = 6000
local TIMEOUT_EXACT = 3000

local REFS_QUERY = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes { number title updatedAt url state }
    }
    pullRequests(first: 100, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes { number title updatedAt url state isDraft }
    }
  }
}
]]

---@param state? string
---@return 'open'|'closed'|'merged'
local function normalize_state(state)
    if state == 'CLOSED' or state == 'closed' then
        return 'closed'
    end
    if state == 'MERGED' or state == 'merged' then
        return 'merged'
    end
    return 'open'
end

---@param repo config.completion.forge.Repo
---@param cb fun(items: config.completion.forge.RefItem[]?, err: string?)
local function fetch_refs(repo, cb)
    local cmd = {
        'gh',
        'api',
        'graphql',
        '-F',
        'owner=' .. repo.owner,
        '-F',
        'name=' .. repo.repo,
        '-f',
        'query=' .. REFS_QUERY,
    }
    vim.system(cmd, { text = true, timeout = TIMEOUT_LIST }, function(result)
        local err = api.classify_error(result)
        if err then
            api.warn(
                repo,
                err,
                ('forge: gh api failed (%s) for %s'):format(err, repo.key)
            )
            vim.schedule(function()
                cb(nil, err)
            end)
            return
        end
        local data, derr = api.decode_json(result)
        if not data then
            api.warn(repo, 'decode', 'forge: gh api returned invalid JSON')
            vim.schedule(function()
                cb(nil, derr)
            end)
            return
        end
        local repo_data = vim.tbl_get(data, 'data', 'repository') or {}
        local items = {}
        for _, n in ipairs(vim.tbl_get(repo_data, 'issues', 'nodes') or {}) do
            items[#items + 1] = {
                kind = 'issue',
                number = n.number,
                title = n.title or '',
                state = normalize_state(n.state),
                updated = api.parse_iso8601(n.updatedAt),
                url = n.url,
            }
        end
        for _, n in
            ipairs(vim.tbl_get(repo_data, 'pullRequests', 'nodes') or {})
        do
            items[#items + 1] = {
                kind = 'pr',
                number = n.number,
                title = n.title or '',
                state = normalize_state(n.state),
                updated = api.parse_iso8601(n.updatedAt),
                url = n.url,
                draft = n.isDraft and true or false,
            }
        end
        table.sort(items, function(a, b)
            return (a.updated or 0) > (b.updated or 0)
        end)
        vim.schedule(function()
            cb(items, nil)
        end)
    end)
end

---@param repo config.completion.forge.Repo
---@param cb fun(items: config.completion.forge.MentionItem[]?, err: string?)
local function fetch_mentions(repo, cb)
    local results = { assignees = nil, contributors = nil }
    local errors = {}
    local pending = 2

    local function settle()
        pending = pending - 1
        if pending > 0 then
            return
        end
        if not results.assignees and not results.contributors then
            api.warn(
                repo,
                'unavailable',
                ('forge: gh mention fetch failed for %s'):format(repo.key)
            )
            vim.schedule(function()
                cb(nil, errors[1] or 'unavailable')
            end)
            return
        end
        local seen = {}
        local items = {}
        for _, a in ipairs(results.assignees or {}) do
            if a.login and not seen[a.login] and a.type ~= 'Bot' then
                seen[a.login] = true
                items[#items + 1] = {
                    login = a.login,
                    source = 'assignee',
                }
            end
        end
        for _, c in ipairs(results.contributors or {}) do
            if c.login and not seen[c.login] and c.type ~= 'Bot' then
                seen[c.login] = true
                items[#items + 1] = {
                    login = c.login,
                    source = 'contributor',
                }
            end
        end
        vim.schedule(function()
            cb(items, nil)
        end)
    end

    local function fetch(path, key)
        vim.system(
            { 'gh', 'api', path },
            { text = true, timeout = TIMEOUT_LIST },
            function(result)
                local err = api.classify_error(result)
                if err then
                    errors[#errors + 1] = err
                    settle()
                    return
                end
                local data, derr = api.decode_json(result)
                if not data then
                    errors[#errors + 1] = derr
                    settle()
                    return
                end
                results[key] = data
                settle()
            end
        )
    end

    fetch(('repos/%s/%s/assignees'):format(repo.owner, repo.repo), 'assignees')
    fetch(
        ('repos/%s/%s/contributors'):format(repo.owner, repo.repo),
        'contributors'
    )
end

---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(item: config.completion.forge.RefItem?, err: string?)
local function fetch_ref_exact(repo, n, cb)
    local path = ('repos/%s/%s/issues/%d'):format(repo.owner, repo.repo, n)
    vim.system(
        { 'gh', 'api', path },
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
            local kind = data.pull_request and 'pr' or 'issue'
            local state = data.state == 'closed' and 'closed' or 'open'
            if
                kind == 'pr'
                and data.pull_request
                and data.pull_request.merged_at
            then
                state = 'merged'
            end
            vim.schedule(function()
                cb({
                    kind = kind,
                    number = data.number,
                    title = data.title or '',
                    state = state,
                    updated = api.parse_iso8601(data.updated_at),
                    url = data.html_url,
                    draft = data.draft and true or false,
                }, nil)
            end)
        end
    )
end

---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(body: string?, err: string?)
local function fetch_ref_doc(repo, n, cb)
    local path = ('repos/%s/%s/issues/%d'):format(repo.owner, repo.repo, n)
    vim.system(
        { 'gh', 'api', path, '--jq', '.body' },
        { text = true, timeout = TIMEOUT_EXACT },
        function(result)
            local err = api.classify_error(result)
            if err then
                vim.schedule(function()
                    cb(nil, err)
                end)
                return
            end
            local body = result.stdout or ''
            body = body:gsub('\r\n', '\n'):gsub('%s+$', '')
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
        return fetch_ref_exact(repo, n, cb)
    end
    cb(nil, 'unsupported_bucket')
end

---@param bucket string
---@param repo config.completion.forge.Repo
---@param n integer
---@param cb fun(body: string?, err: string?)
function M.fetch_doc(bucket, repo, n, cb)
    if bucket == 'refs' then
        return fetch_ref_doc(repo, n, cb)
    end
    cb(nil, 'unsupported_bucket')
end

return M
