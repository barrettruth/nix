local M = {}

local branch_ttl = 30 * 1000
local pr_ttl = 5 * 60 * 1000
local git_info =
    'branch=$(git -C "$1" branch --show-current) || exit; remote=$(git -C "$1" remote get-url origin 2>/dev/null || true); printf "%s\n%s\n" "$branch" "$remote"'

---@class StatusLineRepo
---@field branch string?
---@field pr integer|false|nil
---@field checked integer
---@field pr_checked integer
---@field pending boolean

---@type table<integer, string>
local buffer_roots = {}

---@type table<string, StatusLineRepo>
local repos = {}

local did_setup = false

---@param stdout string?
---@param branch string
---@param filtered boolean
---@return integer?
local function pr_number(stdout, branch, filtered)
    local ok, data = pcall(vim.json.decode, stdout or '')
    if not ok or type(data) ~= 'table' then
        return nil
    end
    for _, item in ipairs(data[1] and data or { data }) do
        if type(item) == 'table' then
            local nr =
                tonumber(item.number or item.iid or item.index or item.id)
            local head = item.head
                or item.headRefName
                or item.source_branch
                or item.sourceBranch
            local matches = type(head) == 'string'
                and (
                    head == branch
                    or vim.endswith(head, ':' .. branch)
                    or vim.endswith(head, '/' .. branch)
                )
            if nr and (filtered or matches) then
                return nr
            end
        end
    end
end

---@param root string
---@param force? boolean
local function refresh(root, force)
    local state = repos[root]
    if not state then
        state = { checked = 0, pr_checked = 0, pending = false }
        repos[root] = state
    end
    if
        state.pending
        or (not force and vim.uv.now() - state.checked < branch_ttl)
    then
        return
    end
    state.pending = true
    if
        not pcall(
            vim.system,
            { 'sh', '-c', git_info, 'sh', root },
            { text = true, timeout = 5000 },
            function(git)
                vim.schedule(function()
                    local now = vim.uv.now()
                    local branch, remote = (git.stdout or ''):match(
                        '([^\n]*)\n([^\n]*)'
                    )
                    if git.code ~= 0 or not branch or branch == '' then
                        state.branch = nil
                        state.pr = nil
                        state.pending = false
                        state.checked = now
                        pcall(vim.cmd.redrawstatus)
                        return
                    end
                    if state.branch ~= branch then
                        state.pr = nil
                        state.pr_checked = 0
                    end
                    state.branch = branch
                    state.checked = now
                    if state.pr ~= nil and now - state.pr_checked < pr_ttl then
                        state.pending = false
                        pcall(vim.cmd.redrawstatus)
                        return
                    end

                    local exe, cmd, filtered
                    remote = (remote or ''):lower()
                    if remote:find('github') then
                        exe, filtered = 'gh', true
                        cmd = {
                            'gh',
                            'pr',
                            'list',
                            '--head',
                            branch,
                            '--json',
                            'number',
                            '--limit',
                            '1',
                        }
                    elseif remote:find('gitlab') then
                        exe, filtered = 'glab', true
                        cmd = {
                            'glab',
                            'mr',
                            'list',
                            '--source-branch',
                            branch,
                            '--output',
                            'json',
                            '--per-page',
                            '1',
                        }
                    elseif remote:find('forge') or remote:find('gitea') then
                        exe, filtered = 'tea', false
                        cmd = {
                            'tea',
                            'pulls',
                            'list',
                            '--state',
                            'open',
                            '--fields',
                            'index,head',
                            '--output',
                            'json',
                            '--limit',
                            '100',
                        }
                    else
                        state.pr = false
                        state.pr_checked = now
                        state.pending = false
                        pcall(vim.cmd.redrawstatus)
                        return
                    end
                    if vim.fn.executable(exe) == 0 then
                        state.pr = false
                        state.pr_checked = now
                        state.pending = false
                        pcall(vim.cmd.redrawstatus)
                        return
                    end
                    if
                        not pcall(
                            vim.system,
                            cmd,
                            { cwd = root, text = true, timeout = 10000 },
                            function(pr)
                                vim.schedule(function()
                                    state.pr = pr.code == 0
                                            and pr_number(
                                                pr.stdout,
                                                branch,
                                                filtered
                                            )
                                        or false
                                    state.pr_checked = vim.uv.now()
                                    state.pending = false
                                    pcall(vim.cmd.redrawstatus)
                                end)
                            end
                        )
                    then
                        state.pr = false
                        state.pr_checked = now
                        state.pending = false
                        pcall(vim.cmd.redrawstatus)
                    end
                end)
            end
        )
    then
        state.pending = false
    end
end

---@param buf? integer
---@param force? boolean
function M.update(buf, force)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local name = vim.api.nvim_buf_get_name(buf)
    if name == '' or vim.bo[buf].buftype ~= '' then
        buffer_roots[buf] = nil
        return
    end
    local root = vim.fs.root(name, '.git')
    buffer_roots[buf] = root
    if root then
        refresh(root, force)
    end
end

function M.setup()
    if did_setup then
        return
    end
    did_setup = true
    local aug = vim.api.nvim_create_augroup('StatusLineMeta', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufFilePost', 'WinEnter' }, {
        group = aug,
        callback = function(args)
            M.update(args.buf ~= 0 and args.buf or nil)
        end,
    })
    vim.api.nvim_create_autocmd(
        { 'DirChanged', 'FocusGained', 'ShellCmdPost' },
        {
            group = aug,
            callback = function(args)
                M.update(args.buf ~= 0 and args.buf or nil, true)
            end,
        }
    )
    vim.api.nvim_create_autocmd('User', {
        group = aug,
        pattern = 'FugitiveChanged',
        callback = function()
            M.update(nil, true)
        end,
    })
    M.update()
end

---@return string
function M.render()
    local name = vim.fn.expand('%')
    local path = ''
    if name ~= '' then
        local state = repos[buffer_roots[vim.api.nvim_get_current_buf()]]
        local prefix = state
                and (state.pr and ('%s/#%s'):format(state.branch, state.pr) or state.branch)
            or nil
        path = ('%%#Directory#%s%s%%* '):format(
            prefix and prefix:gsub('%%', '%%%%') .. ' ' or '',
            vim.fn.expand('%:~'):gsub('%%', '%%%%')
        )
    end
    local buftype = vim.bo.buftype
    local flags = buftype == 'terminal' and '%h%r' or '%h%m%r'
    local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or buftype
    return (' %s%s%%=%%c:%%l/%%L %s '):format(path, flags, filetype)
end

return M
