local forge = require('forge')

---@type forge.Forge
local M = {
    name = 'github',
    cli = 'gh',
    kinds = { issue = 'issue', pr = 'pr' },
    labels = { issue = 'Issues', pr = 'PRs', pr_full = 'Pull Requests', ci = 'CI/CD' },
}

local function nwo()
    local url = forge.remote_web_url()
    return url:match('github%.com/(.+)$') or ''
end

---@param kind string
---@param state string
---@return string
function M:list_cmd(kind, state)
    return ('gh %s list --limit 100 --state %s'):format(kind, state)
end

---@param state string
---@return string[]
function M:list_pr_json_cmd(state)
    return {
        'gh',
        'pr',
        'list',
        '--limit',
        '100',
        '--state',
        state,
        '--json',
        'number,title,headRefName,state',
    }
end

---@param state string
---@return string[]
function M:list_issue_json_cmd(state)
    return {
        'gh',
        'issue',
        'list',
        '--limit',
        '100',
        '--state',
        state,
        '--json',
        'number,title,state',
    }
end

---@return { number: string, title: string, branch: string, state: string }
function M:pr_json_fields()
    return {
        number = 'number',
        title = 'title',
        branch = 'headRefName',
        state = 'state',
    }
end

---@return { number: string, title: string, state: string }
function M:issue_json_fields()
    return { number = 'number', title = 'title', state = 'state' }
end

---@param kind string
---@param num string
function M:view_web(kind, num)
    vim.system({ 'gh', kind, 'view', num, '--web' })
end

---@param loc string
---@param branch string
function M:browse(loc, branch)
    vim.system({ 'gh', 'browse', loc, '--branch', branch })
end

function M:browse_root()
    vim.system({ 'gh', 'browse' })
end

function M:browse_branch(branch)
    vim.system({ 'gh', 'browse', '--branch', branch })
end

function M:browse_commit(sha)
    vim.system({ 'gh', 'browse', sha })
end

function M:checkout_cmd(num)
    return { 'gh', 'pr', 'checkout', num }
end

---@param loc string
function M:yank_branch(loc)
    forge.yank_url({ 'gh', 'browse', loc, '-n' })
end

---@param loc string
function M:yank_commit(loc)
    forge.yank_url({ 'gh', 'browse', loc, '--commit=last', '-n' })
end

---@param num string
---@return string[]
function M:fetch_pr(num)
    return { 'git', 'fetch', 'origin', ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num)
    return {
        'gh',
        'pr',
        'view',
        num,
        '--json',
        'baseRefName',
        '--jq',
        '.baseRefName',
    }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch)
    return {
        'gh',
        'pr',
        'list',
        '--head',
        branch,
        '--json',
        'number',
        '--jq',
        '.[0].number',
    }
end

---@param num string
---@return string
function M:checks_cmd(num)
    return ('gh pr checks %s'):format(num)
end

---@param num string
---@return string[]
function M:checks_json_cmd(num)
    return {
        'gh',
        'pr',
        'checks',
        num,
        '--json',
        'name,bucket,link,state,startedAt,completedAt',
    }
end

---@param run_id string
---@param failed_only boolean
---@return string[]
function M:check_log_cmd(run_id, failed_only)
    local lines = forge.config().ci.lines
    local flag = failed_only and '--log-failed' or '--log'
    return {
        'sh',
        '-c',
        ('gh run view %s -R %s %s | tail -n %d'):format(
            run_id,
            nwo(),
            flag,
            lines
        ),
    }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id)
    return { 'gh', 'run', 'watch', run_id, '-R', nwo() }
end

function M:list_runs_json_cmd(branch)
    local cmd = {
        'gh', 'run', 'list',
        '--json', 'databaseId,name,headBranch,status,conclusion,event,url,createdAt',
        '--limit', '30',
    }
    if branch then
        table.insert(cmd, '--branch')
        table.insert(cmd, branch)
    end
    return cmd
end

function M:normalize_run(entry)
    local status = entry.status or ''
    if status == 'completed' then
        status = entry.conclusion or 'unknown'
    end
    return {
        id = tostring(entry.databaseId or ''),
        name = entry.name or '',
        branch = entry.headBranch or '',
        status = status,
        event = entry.event or '',
        url = entry.url or '',
        created_at = entry.createdAt or '',
    }
end

function M:run_log_cmd(id, failed_only)
    local lines = forge.config().ci.lines
    local flag = failed_only and '--log-failed' or '--log'
    return {
        'sh', '-c',
        ('gh run view %s -R %s %s | tail -n %d'):format(
            id, nwo(), flag, lines
        ),
    }
end

function M:run_tail_cmd(id)
    return { 'gh', 'run', 'watch', id, '-R', nwo() }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method)
    return { 'gh', 'pr', 'merge', num, '--' .. method }
end

---@param num string
---@return string[]
function M:approve_cmd(num)
    return { 'gh', 'pr', 'review', num, '--approve' }
end

---@return forge.RepoInfo
function M:repo_info()
    local result = vim.system({
        'gh',
        'repo',
        'view',
        nwo(),
        '--json',
        'viewerPermission,squashMergeAllowed,rebaseMergeAllowed,mergeCommitAllowed',
    }, { text = true }):wait()

    local data = vim.json.decode(result.stdout or '{}') or {}
    local methods = {}
    if data.squashMergeAllowed then
        table.insert(methods, 'squash')
    end
    if data.rebaseMergeAllowed then
        table.insert(methods, 'rebase')
    end
    if data.mergeCommitAllowed then
        table.insert(methods, 'merge')
    end

    return {
        permission = (data.viewerPermission or 'READ'):upper(),
        merge_methods = methods,
    }
end

---@param num string
---@return forge.PRState
function M:pr_state(num)
    local result = vim.system({
        'gh',
        'pr',
        'view',
        num,
        '--json',
        'state,mergeable,reviewDecision',
    }, { text = true }):wait()

    local data = vim.json.decode(result.stdout or '{}') or {}
    return {
        state = data.state or 'UNKNOWN',
        mergeable = data.mergeable or 'UNKNOWN',
        review_decision = data.reviewDecision or '',
    }
end

return M
