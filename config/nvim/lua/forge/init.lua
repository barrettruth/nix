local M = {}

---@class forge.PRState
---@field state string
---@field mergeable string
---@field review_decision string

---@class forge.Check
---@field name string
---@field status string
---@field elapsed string
---@field run_id string

---@class forge.RepoInfo
---@field permission string
---@field merge_methods string[]

---@class forge.Forge
---@field name string
---@field cli string
---@field kinds { issue: string, pr: string }
---@field labels { issue: string, pr: string }
---@field list_cmd fun(self: forge.Forge, kind: string, state: string): string
---@field list_pr_json_cmd fun(self: forge.Forge, state: string): string[]
---@field list_issue_json_cmd fun(self: forge.Forge, state: string): string[]
---@field pr_json_fields fun(self: forge.Forge): { number: string, title: string, branch: string, state: string }
---@field issue_json_fields fun(self: forge.Forge): { number: string, title: string, state: string }
---@field view_web fun(self: forge.Forge, kind: string, num: string)
---@field browse fun(self: forge.Forge, loc: string, branch: string)
---@field browse_root fun(self: forge.Forge)
---@field yank_branch fun(self: forge.Forge, loc: string)
---@field yank_commit fun(self: forge.Forge, loc: string)
---@field fetch_pr fun(self: forge.Forge, num: string): string[]
---@field pr_base_cmd fun(self: forge.Forge, num: string): string[]
---@field pr_for_branch_cmd fun(self: forge.Forge, branch: string): string[]
---@field checks_cmd fun(self: forge.Forge, num: string): string
---@field check_log_cmd fun(self: forge.Forge, run_id: string, failed_only: boolean): string[]
---@field check_tail_cmd fun(self: forge.Forge, run_id: string): string[]
---@field merge_cmd fun(self: forge.Forge, num: string, method: string): string[]
---@field approve_cmd fun(self: forge.Forge, num: string): string[]
---@field repo_info fun(self: forge.Forge): forge.RepoInfo
---@field pr_state fun(self: forge.Forge, num: string): forge.PRState

---@type table<string, forge.Forge>
local forge_cache = {}

---@type table<string, forge.RepoInfo>
local repo_info_cache = {}

---@type table<string, string>
local root_cache = {}

---@return string?
local function git_root()
    local cwd = vim.fn.getcwd()
    if root_cache[cwd] then
        return root_cache[cwd]
    end
    local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
    if vim.v.shell_error ~= 0 then
        return nil
    end
    root_cache[cwd] = root
    return root
end

---@param remote string
---@return string? forge_name
local function detect_from_remote(remote)
    if remote:find('github') and vim.fn.executable('gh') == 1 then
        return 'github'
    end
    if remote:find('gitlab') and vim.fn.executable('glab') == 1 then
        return 'gitlab'
    end
    if
        (
            remote:find('codeberg')
            or remote:find('gitea')
            or remote:find('forgejo')
        ) and vim.fn.executable('tea') == 1
    then
        return 'codeberg'
    end
    return nil
end

---@return forge.Forge?
function M.detect()
    local root = git_root()
    if not root then
        return nil
    end
    if forge_cache[root] then
        return forge_cache[root]
    end
    local remote = vim.trim(vim.fn.system('git remote get-url origin'))
    if vim.v.shell_error ~= 0 then
        return nil
    end
    local name = detect_from_remote(remote)
    if not name then
        return nil
    end
    local forge = require('forge.' .. name)
    forge_cache[root] = forge
    return forge
end

---@param forge forge.Forge
---@return forge.RepoInfo
function M.repo_info(forge)
    local root = git_root()
    if root and repo_info_cache[root] then
        return repo_info_cache[root]
    end
    local info = forge:repo_info()
    if root then
        repo_info_cache[root] = info
    end
    return info
end

function M.clear_cache()
    forge_cache = {}
    repo_info_cache = {}
    root_cache = {}
end

---@return string
function M.file_loc()
    local root = git_root()
    if not root then
        return vim.fn.expand('%:t')
    end
    local file = vim.api.nvim_buf_get_name(0):sub(#root + 2)
    local mode = vim.fn.mode()
    if mode:match('[vV]') or mode == '\22' then
        local s = vim.fn.line('v')
        local e = vim.fn.line('.')
        if s > e then
            s, e = e, s
        end
        if s == e then
            return ('%s:%d'):format(file, s)
        end
        return ('%s:%d-%d'):format(file, s, e)
    end
    return ('%s:%d'):format(file, vim.fn.line('.'))
end

---@return string
function M.remote_web_url()
    local root = git_root()
    if not root then
        return ''
    end
    local remote = vim.trim(vim.fn.system('git remote get-url origin'))
    remote = remote:gsub('%.git$', '')
    remote = remote:gsub('^ssh://git@', 'https://')
    remote = remote:gsub('^git@([^:]+):', 'https://%1/')
    return remote
end

---@param s string
---@param width integer
---@return string
local function pad_or_truncate(s, width)
    local len = #s
    if len > width then
        return s:sub(1, width - 1) .. '…'
    end
    return s .. string.rep(' ', width - len)
end

---@param state string
---@return string
local function state_color(state)
    local s = state:lower()
    if s == 'open' or s == 'opened' then
        return '\27[32m'
    end
    if s == 'merged' then
        return '\27[35m'
    end
    return '\27[31m'
end

---@param entry table
---@param fields { number: string, title: string, branch: string, state: string }
---@return string
function M.format_pr(entry, fields)
    local num = tostring(entry[fields.number] or '')
    local title = entry[fields.title] or ''
    local branch = entry[fields.branch] or ''
    local state = entry[fields.state] or ''
    return ('\27[34m#%-4s\27[0m %s \27[2m%s\27[0m %s%s\27[0m'):format(
        num,
        pad_or_truncate(title, 40),
        pad_or_truncate(branch, 20),
        state_color(state),
        state:lower()
    )
end

---@param entry table
---@param fields { number: string, title: string, state: string }
---@return string
function M.format_issue(entry, fields)
    local num = tostring(entry[fields.number] or '')
    local title = entry[fields.title] or ''
    local state = entry[fields.state] or ''
    return ('\27[34m#%-4s\27[0m %s %s%s\27[0m'):format(
        num,
        pad_or_truncate(title, 50),
        state_color(state),
        state:lower()
    )
end

---@param check table
---@return string
function M.format_check(check)
    local bucket = (check.bucket or 'pending'):lower()
    local name = check.name or ''
    local icon, color
    if bucket == 'pass' then
        icon, color = '✓', '\27[32m'
    elseif bucket == 'fail' then
        icon, color = '✗', '\27[31m'
    elseif bucket == 'pending' then
        icon, color = '●', '\27[33m'
    elseif bucket == 'skipping' or bucket == 'cancel' then
        icon, color = '○', '\27[2m'
    else
        icon, color = '?', '\27[2m'
    end
    local elapsed = ''
    if check.startedAt and check.completedAt and check.completedAt ~= '' then
        local ok_s, ts =
            pcall(vim.fn.strptime, '%Y-%m-%dT%H:%M:%SZ', check.startedAt)
        local ok_e, te =
            pcall(vim.fn.strptime, '%Y-%m-%dT%H:%M:%SZ', check.completedAt)
        if ok_s and ok_e and ts > 0 and te > 0 then
            local secs = te - ts
            if secs >= 60 then
                elapsed = ('%dm%ds'):format(math.floor(secs / 60), secs % 60)
            else
                elapsed = ('%ds'):format(secs)
            end
        end
    end
    local run_id = ''
    if check.link then
        run_id = check.link:match('/actions/runs/(%d+)') or ''
    end
    return ('%s%s\27[0m %s %s \27[2m%s\27[0m'):format(
        color,
        icon,
        pad_or_truncate(name, 30),
        pad_or_truncate(elapsed, 8),
        run_id
    )
end

---@param checks table[]
---@param filter string?
---@return table[]
function M.filter_checks(checks, filter)
    if not filter or filter == 'all' then
        table.sort(checks, function(a, b)
            local order =
                { fail = 1, pending = 2, pass = 3, skipping = 4, cancel = 5 }
            local oa = order[(a.bucket or ''):lower()] or 9
            local ob = order[(b.bucket or ''):lower()] or 9
            return oa < ob
        end)
        return checks
    end
    local filtered = {}
    for _, c in ipairs(checks) do
        if (c.bucket or ''):lower() == filter then
            table.insert(filtered, c)
        end
    end
    return filtered
end

---@param args string[]
function M.yank_url(args)
    vim.system(args, { text = true }, function(result)
        if result.code == 0 then
            local url = vim.trim(result.stdout or '')
            if url ~= '' then
                vim.schedule(function()
                    vim.fn.setreg('+', url)
                end)
            end
        end
    end)
end

return M
