local forge = require('forge')

---@type forge.Forge
local M = {
    name = 'codeberg',
    cli = 'tea',
    kinds = { issue = 'issues', pr = 'pulls' },
    labels = { issue = 'Issues', pr = 'PRs' },
}

---@param kind string
---@param state string
---@return string
function M:list_cmd(kind, state)
    return ('tea %s list --state %s'):format(kind, state)
end

---@param state string
---@return string[]
function M:list_pr_json_cmd(state)
    return {
        'tea',
        'pulls',
        'list',
        '--state',
        state,
        '--output',
        'json',
        '--fields',
        'index,title,head,state',
    }
end

---@param state string
---@return string[]
function M:list_issue_json_cmd(state)
    return {
        'tea',
        'issues',
        'list',
        '--state',
        state,
        '--output',
        'json',
        '--fields',
        'index,title,state',
    }
end

---@return { number: string, title: string, branch: string, state: string }
function M:pr_json_fields()
    return {
        number = 'index',
        title = 'title',
        branch = 'head',
        state = 'state',
    }
end

---@return { number: string, title: string, state: string }
function M:issue_json_fields()
    return { number = 'index', title = 'title', state = 'state' }
end

---@param kind string
---@param num string
function M:view_web(kind, num)
    local slug = kind == 'pulls' and 'pulls' or 'issues'
    local base = forge.remote_web_url()
    vim.ui.open(('%s/%s/%s'):format(base, slug, num))
end

---@param loc string
---@param branch string
function M:browse(loc, branch)
    local base = forge.remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    vim.ui.open(('%s/src/branch/%s/%s#L%s'):format(base, branch, file, lines))
end

function M:browse_root()
    vim.ui.open(forge.remote_web_url())
end

---@param loc string
function M:yank_branch(loc)
    local branch = vim.trim(vim.fn.system('git branch --show-current'))
    local base = forge.remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    vim.fn.setreg(
        '+',
        ('%s/src/branch/%s/%s#L%s'):format(base, branch, file, lines)
    )
end

---@param loc string
function M:yank_commit(loc)
    local commit = vim.trim(vim.fn.system('git rev-parse HEAD'))
    local base = forge.remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    vim.fn.setreg(
        '+',
        ('%s/src/commit/%s/%s#L%s'):format(base, commit, file, lines)
    )
end

---@param num string
---@return string[]
function M:fetch_pr(num)
    return { 'git', 'fetch', 'origin', ('pull/%s/head:pr-%s'):format(num, num) }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num)
    return { 'tea', 'pr', num, '--fields', 'base', '--output', 'simple' }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(_branch)
    return {
        'tea',
        'pr',
        'list',
        '--fields',
        'index,head',
        '--output',
        'simple',
        '--state',
        'open',
    }
end

---@param num string
---@return string
function M:checks_cmd(num)
    local _ = num
    return 'tea actions runs list'
end

---@param run_id string
---@param failed_only boolean
---@return string[]
function M:check_log_cmd(run_id, failed_only)
    local _ = failed_only
    local lines = forge.config().ci.lines
    return {
        'sh',
        '-c',
        ('tea actions runs logs %s | tail -n %d'):format(run_id, lines),
    }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id)
    return { 'tea', 'actions', 'runs', 'logs', run_id, '--follow' }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method)
    return { 'tea', 'pr', 'merge', num, '--style', method }
end

---@param num string
---@return string[]
function M:approve_cmd(num)
    return { 'tea', 'pr', 'approve', num }
end

---@return forge.RepoInfo
function M:repo_info()
    return {
        permission = 'ADMIN',
        merge_methods = { 'squash', 'rebase', 'merge' },
    }
end

---@param num string
---@return forge.PRState
function M:pr_state(num)
    local result = vim.system(
        { 'tea', 'pr', num, '--fields', 'state,mergeable', '--output', 'json' },
        { text = true }
    ):wait()
    local data = vim.json.decode(result.stdout or '{}') or {}
    return {
        state = (data.state or 'unknown'):upper(),
        mergeable = data.mergeable and 'MERGEABLE' or 'UNKNOWN',
        review_decision = '',
    }
end

return M
