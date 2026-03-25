local forge = require('forge')

---@type forge.Forge
local M = {
    name = 'gitlab',
    cli = 'glab',
    kinds = { issue = 'issue', pr = 'mr' },
    labels = {
        issue = 'Issues',
        pr = 'MRs',
        pr_full = 'Merge Requests',
        ci = 'CI/CD',
    },
}

---@param kind string
---@param state string
---@return string
function M:list_cmd(kind, state)
    local cmd = ('glab %s list --per-page 100'):format(kind)
    if state == 'closed' then
        cmd = cmd .. ' --closed'
    elseif state == 'all' then
        cmd = cmd .. ' --all'
    end
    return cmd
end

---@param state string
---@return string[]
function M:list_pr_json_cmd(state)
    local cmd = {
        'glab',
        'mr',
        'list',
        '--per-page',
        '100',
        '--output',
        'json',
    }
    if state == 'closed' then
        table.insert(cmd, '--closed')
    elseif state == 'all' then
        table.insert(cmd, '--all')
    end
    return cmd
end

---@param state string
---@return string[]
function M:list_issue_json_cmd(state)
    local cmd = {
        'glab',
        'issue',
        'list',
        '--per-page',
        '100',
        '--output',
        'json',
    }
    if state == 'closed' then
        table.insert(cmd, '--closed')
    elseif state == 'all' then
        table.insert(cmd, '--all')
    end
    return cmd
end

function M:pr_json_fields()
    return {
        number = 'iid',
        title = 'title',
        branch = 'source_branch',
        state = 'state',
        author = 'author',
        created_at = 'created_at',
    }
end

function M:issue_json_fields()
    return {
        number = 'iid',
        title = 'title',
        state = 'state',
        author = 'author',
        created_at = 'created_at',
    }
end

---@param kind string
---@param num string
function M:view_web(kind, num)
    vim.system({ 'glab', kind, 'view', num, '--web' })
end

---@param loc string
---@param branch string
function M:browse(loc, branch)
    local base = forge.remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    vim.ui.open(('%s/-/blob/%s/%s#L%s'):format(base, branch, file, lines))
end

function M:browse_root()
    vim.system({ 'glab', 'repo', 'view', '--web' })
end

function M:browse_branch(branch)
    local base = forge.remote_web_url()
    vim.ui.open(base .. '/-/tree/' .. branch)
end

function M:browse_commit(sha)
    local base = forge.remote_web_url()
    vim.ui.open(base .. '/-/commit/' .. sha)
end

function M:checkout_cmd(num)
    return { 'glab', 'mr', 'checkout', num }
end

---@param loc string
function M:yank_branch(loc)
    local branch = vim.trim(vim.fn.system('git branch --show-current'))
    local base = forge.remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    vim.fn.setreg(
        '+',
        ('%s/-/blob/%s/%s#L%s'):format(base, branch, file, lines)
    )
end

---@param loc string
function M:yank_commit(loc)
    local commit = vim.trim(vim.fn.system('git rev-parse HEAD'))
    local base = forge.remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    vim.fn.setreg(
        '+',
        ('%s/-/blob/%s/%s#L%s'):format(base, commit, file, lines)
    )
end

---@param num string
---@return string[]
function M:fetch_pr(num)
    return {
        'git',
        'fetch',
        'origin',
        ('merge-requests/%s/head:mr-%s'):format(num, num),
    }
end

---@param num string
---@return string[]
function M:pr_base_cmd(num)
    return {
        'sh',
        '-c',
        ('glab mr view %s -F json | jq -r .target_branch'):format(num),
    }
end

---@param branch string
---@return string[]
function M:pr_for_branch_cmd(branch)
    return {
        'sh',
        '-c',
        ("glab mr list --source-branch '%s' -F json | jq -r '.[0].iid // empty'"):format(
            branch
        ),
    }
end

---@param num string
---@return string
function M:checks_cmd(num)
    local _ = num
    return 'glab ci list'
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
        ('glab ci trace %s | tail -n %d'):format(run_id, lines),
    }
end

---@param run_id string
---@return string[]
function M:check_tail_cmd(run_id)
    return { 'glab', 'ci', 'trace', run_id }
end

function M:list_runs_json_cmd(branch)
    local cmd = {
        'glab',
        'ci',
        'list',
        '--output',
        'json',
        '--per-page',
        '30',
    }
    if branch then
        table.insert(cmd, '--ref')
        table.insert(cmd, branch)
    end
    return cmd
end

function M:normalize_run(entry)
    local ref = entry.ref or ''
    local mr_num = ref:match('^refs/merge%-requests/(%d+)/head$')
    return {
        id = tostring(entry.id or ''),
        name = mr_num and ('!%s'):format(mr_num) or ref,
        branch = '',
        status = entry.status or '',
        event = entry.source or '',
        url = entry.web_url or '',
        created_at = entry.created_at or '',
    }
end

function M:run_log_cmd(id, failed_only)
    local lines = forge.config().ci.lines
    local jq_filter = failed_only
            and '[.[] | select(.status=="failed")][0].id // .[0].id'
        or '.[0].id'
    return {
        'sh',
        '-c',
        ('JOB=$(glab api \'projects/:id/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB" | tail -n %d'):format(
            id,
            jq_filter,
            lines
        ),
    }
end

function M:run_tail_cmd(id)
    local jq_filter =
        '[.[] | select(.status=="running" or .status=="pending")][0].id // .[0].id'
    return {
        'sh',
        '-c',
        ('JOB=$(glab api \'projects/:id/pipelines/%s/jobs?per_page=100\' | jq -r \'%s\') && [ "$JOB" != "null" ] && glab ci trace "$JOB"'):format(
            id,
            jq_filter
        ),
    }
end

---@param num string
---@param method string
---@return string[]
function M:merge_cmd(num, method)
    local cmd = { 'glab', 'mr', 'merge', num }
    if method == 'squash' then
        table.insert(cmd, '--squash')
    elseif method == 'rebase' then
        table.insert(cmd, '--rebase')
    end
    return cmd
end

---@param num string
---@return string[]
function M:approve_cmd(num)
    return { 'glab', 'mr', 'approve', num }
end

---@return forge.RepoInfo
function M:repo_info()
    local result = vim.system(
        { 'glab', 'api', 'projects/:id' },
        { text = true }
    )
        :wait()
    local data = vim.json.decode(result.stdout or '{}') or {}
    local perms = data.permissions or {}
    local access = (perms.project_access or {}).access_level or 0
    local group_access = (perms.group_access or {}).access_level or 0
    local level = math.max(access, group_access)

    local permission = 'READ'
    if level >= 40 then
        permission = 'ADMIN'
    elseif level >= 30 then
        permission = 'WRITE'
    end

    local methods = {}
    local merge_method = data.merge_method or 'merge'
    if merge_method == 'ff' or merge_method == 'rebase_merge' then
        table.insert(methods, 'rebase')
    else
        table.insert(methods, 'merge')
    end
    if data.squash_option ~= 'never' then
        table.insert(methods, 'squash')
    end

    return {
        permission = permission,
        merge_methods = methods,
    }
end

---@param num string
---@return forge.PRState
function M:pr_state(num)
    local result = vim.system(
        { 'glab', 'mr', 'view', num, '--output', 'json' },
        { text = true }
    ):wait()
    local data = vim.json.decode(result.stdout or '{}') or {}
    return {
        state = (data.state or 'unknown'):upper(),
        mergeable = data.merge_status or 'unknown',
        review_decision = '',
    }
end

return M
