local function make_header(bindings)
    local utils = require('fzf-lua.utils')
    local parts = {}
    for _, b in ipairs(bindings) do
        local key = utils.ansi_from_hl('FzfLuaHeaderBind', '<' .. b[1] .. '>')
        local desc = utils.ansi_from_hl('FzfLuaHeaderText', b[2])
        table.insert(parts, key .. ' to ' .. desc)
    end
    return ':: ' .. table.concat(parts, '|')
end

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
local function checks_picker(f, num, filter, cached_checks)
    filter = filter or 'all'
    require('lz.n').trigger_load('ibhagwan/fzf-lua')
    local forge_mod = require('forge')

    local function open_picker(checks)
        local filtered = forge_mod.filter_checks(checks, filter)
        local lines = {}
        for i, c in ipairs(filtered) do
            local line = ('%d\t%s'):format(i, forge_mod.format_check(c))
            table.insert(lines, line)
        end

        local function get_check(selected)
            if not selected[1] then
                return nil
            end
            local idx = tonumber(selected[1]:match('^(%d+)'))
            return idx and filtered[idx] or nil
        end

        local labels = {
            all = 'all',
            fail = 'failed',
            pass = 'passed',
            pending = 'running',
        }

        require('fzf-lua').fzf_exec(lines, {
            prompt = ('Checks (#%s, %s)> '):format(
                num,
                labels[filter] or filter
            ),
            fzf_opts = {
                ['--ansi'] = '',
                ['--no-multi'] = '',
                ['--with-nth'] = '2..',
                ['--delimiter'] = '\t',
                ['--header'] = make_header({
                    { 'enter', 'view log' },
                    { 'ctrl-x', 'open in browser' },
                    { 'ctrl-f', 'failed' },
                    { 'ctrl-p', 'passed' },
                    { 'ctrl-n', 'running' },
                    { 'ctrl-a', 'all' },
                    { 'ctrl-r', 'refresh' },
                }),
            },
            actions = {
                ['default'] = function(selected)
                    local c = get_check(selected)
                    if not c then
                        return
                    end
                    local run_id = (c.link or ''):match('/actions/runs/(%d+)')
                    if not run_id then
                        return
                    end
                    forge_mod.log_now('fetching check logs...')
                    local bucket = (c.bucket or ''):lower()
                    local cmd
                    if bucket == 'pending' then
                        cmd = f:check_tail_cmd(run_id)
                    else
                        cmd = f:check_log_cmd(run_id, bucket == 'fail')
                    end
                    vim.cmd('noautocmd botright new')
                    vim.fn.termopen(cmd)
                    vim.api.nvim_feedkeys(
                        vim.api.nvim_replace_termcodes('<C-\\><C-n>G', true, false, true),
                        'n', false
                    )
                    if c.link then
                        vim.b.forge_check_url = c.link
                        vim.keymap.set('n', 'gx', function()
                            vim.ui.open(vim.b.forge_check_url)
                        end, { buffer = true, desc = 'open check in browser' })
                    end
                end,
                ['ctrl-x'] = function(selected)
                    local c = get_check(selected)
                    if c and c.link then
                        vim.ui.open(c.link)
                    end
                end,
                ['ctrl-f'] = function()
                    checks_picker(f, num, 'fail', checks)
                end,
                ['ctrl-p'] = function()
                    checks_picker(f, num, 'pass', checks)
                end,
                ['ctrl-n'] = function()
                    checks_picker(f, num, 'pending', checks)
                end,
                ['ctrl-a'] = function()
                    checks_picker(f, num, 'all', checks)
                end,
                ['ctrl-r'] = function()
                    checks_picker(f, num, filter)
                end,
            },
        })
    end

    if cached_checks then
        forge_mod.log('checks picker (PR #' .. num .. ', cached)')
        open_picker(cached_checks)
        return
    end

    if f.checks_json_cmd then
        forge_mod.log_now('fetching checks for PR #' .. num .. '...')
        vim.system(f:checks_json_cmd(num), { text = true }, function(result)
            vim.schedule(function()
                local ok, checks = pcall(vim.json.decode, result.stdout or '[]')
                if ok and checks then
                    open_picker(checks)
                else
                    vim.notify('[forge]: no checks found', vim.log.levels.INFO)
                    vim.cmd.redraw()
                end
            end)
        end)
    else
        require('fzf-lua').fzf_exec(f:checks_cmd(num), {
            prompt = ('Checks (#%s)> '):format(num),
            fzf_opts = { ['--ansi'] = '' },
            actions = {
                ['ctrl-r'] = function()
                    checks_picker(f, num, filter)
                end,
            },
        })
    end
end

---@param f forge.Forge
---@param num string
---@return table<string, function>
local function pr_actions(f, num)
    local info = require('forge').repo_info(f)
    local can_write = info.permission == 'ADMIN'
        or info.permission == 'MAINTAIN'
        or info.permission == 'WRITE'
    local actions = {}

    actions['default'] = function()
        local checkout = f:checkout_cmd(num)
        require('forge').log_now('checking out PR #' .. num .. '...')
        vim.system(checkout, { text = true }, function(result)
            vim.schedule(function()
                if result.code == 0 then
                    vim.notify(('[forge]: checked out PR #%s'):format(num))
                    vim.cmd.redraw()
                else
                    vim.notify(
                        '[forge]: ' .. (result.stderr or 'checkout failed'),
                        vim.log.levels.ERROR
                    )
                    vim.cmd.redraw()
                end
            end)
        end)
    end

    actions['ctrl-x'] = function()
        f:view_web(f.kinds.pr, num)
    end

    actions['ctrl-d'] = function()
        local forge_mod = require('forge')
        local review = forge_mod.review
        local repo_root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
        local checkout_cmd = f:checkout_cmd(num)

        forge_mod.log_now('reviewing PR #' .. num .. '...')
        vim.system(checkout_cmd, { text = true }, function(co_result)
            if co_result.code ~= 0 then
                vim.schedule(function()
                    forge_mod.log('checkout skipped, proceeding with diff')
                end)
            end

            vim.system(
                f:pr_base_cmd(num),
                { text = true },
                function(base_result)
                    vim.schedule(function()
                        local base = vim.trim(base_result.stdout or '')
                        if base == '' or base_result.code ~= 0 then
                            base = 'main'
                        end
                        local range = 'origin/' .. base
                        review.base = range
                        review.mode = 'unified'
                        require('diffs.commands').greview(range, { repo_root = repo_root })
                        forge_mod.log(
                            'review ready for PR #' .. num .. ' against ' .. base
                        )
                    end)
                end
            )
        end)
    end

    actions['ctrl-t'] = function()
        checks_picker(f, num)
    end

    if can_write then
        actions['ctrl-a'] = function()
            require('forge').log_now('approving PR #' .. num .. '...')
            vim.system(f:approve_cmd(num), { text = true }, function(result)
                vim.schedule(function()
                    if result.code == 0 then
                        vim.notify(('[forge]: approved PR #%s'):format(num))
                        vim.cmd.redraw()
                    else
                        vim.notify(
                            '[forge]: ' .. (result.stderr or 'approve failed'),
                            vim.log.levels.ERROR
                        )
                        vim.cmd.redraw()
                    end
                end)
            end)
        end

        if #info.merge_methods > 0 then
            actions['ctrl-m'] = function()
                if #info.merge_methods == 1 then
                    require('forge').log_now('merging PR #' .. num .. ' (' .. info.merge_methods[1] .. ')...')
                    vim.system(
                        f:merge_cmd(num, info.merge_methods[1]),
                        { text = true },
                        function(result)
                            vim.schedule(function()
                                if result.code == 0 then
                                    vim.notify(
                                        ('[forge]: merged PR #%s (%s)'):format(
                                            num,
                                            info.merge_methods[1]
                                        )
                                    )
                                    vim.cmd.redraw()
                                else
                                    vim.notify(
                                        '[forge]: ' .. (result.stderr or 'merge failed'),
                                        vim.log.levels.ERROR
                                    )
                                    vim.cmd.redraw()
                                end
                            end)
                        end
                    )
                else
                    vim.schedule(function()
                        vim.ui.select(info.merge_methods, {
                            prompt = 'Merge method: ',
                        }, function(method)
                            if not method then
                                return
                            end
                            require('forge').log_now('merging PR #' .. num .. ' (' .. method .. ')...')
                            vim.system(
                                f:merge_cmd(num, method),
                                { text = true },
                                function(result)
                                    vim.schedule(function()
                                        if result.code == 0 then
                                            vim.notify(
                                                ('[forge]: merged PR #%s (%s)'):format(
                                                    num,
                                                    method
                                                )
                                            )
                                            vim.cmd.redraw()
                                        else
                                            vim.notify(
                                                '[forge]: ' .. (result.stderr or 'merge failed'),
                                                vim.log.levels.ERROR
                                            )
                                            vim.cmd.redraw()
                                        end
                                    end)
                                end
                            )
                        end)
                    end)
                end
            end
        end
    end

    return actions
end

---@param kind 'issue'|'pr'
---@param state 'all'|'open'|'closed'
---@param f forge.Forge
local function forge_picker(kind, state, f)
    local cli_kind = f.kinds[kind]
    local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
    require('lz.n').trigger_load('ibhagwan/fzf-lua')

    local forge_mod = require('forge')
    local cache_key = forge_mod.list_key(kind, state)

    if kind == 'pr' then
        local pr_fields = f:pr_json_fields()

        local function open_pr_list(prs)
            local lines = {}
            for _, pr in ipairs(prs) do
                table.insert(lines, forge_mod.format_pr(pr, pr_fields))
            end
            require('fzf-lua').fzf_exec(lines, {
                prompt = ('%s (%s)> '):format(f.labels[kind], state),
                fzf_opts = {
                    ['--ansi'] = '',
                    ['--no-multi'] = '',
                    ['--header'] = make_header({
                        { 'enter', 'checkout' },
                        { 'ctrl-d', 'review diff' },
                        { 'ctrl-t', 'checks' },
                        { 'ctrl-x', 'open in browser' },
                        { 'ctrl-o', 'toggle state' },
                        { 'ctrl-r', 'refresh' },
                        { 'ctrl-a', 'approve' },
                        { 'ctrl-m', 'merge' },
                    }),
                },
                actions = {
                    ['default'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if num then
                            pr_actions(f, num)['default']()
                        end
                    end,
                    ['ctrl-x'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if num then
                            f:view_web(cli_kind, num)
                        end
                    end,
                    ['ctrl-d'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if num then
                            pr_actions(f, num)['ctrl-d']()
                        end
                    end,
                    ['ctrl-t'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if num then
                            checks_picker(f, num)
                        end
                    end,
                    ['ctrl-a'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if not num then
                            return
                        end
                        local acts = pr_actions(f, num)
                        if acts['ctrl-a'] then
                            acts['ctrl-a']()
                        end
                    end,
                    ['ctrl-m'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if not num then
                            return
                        end
                        local acts = pr_actions(f, num)
                        if acts['ctrl-m'] then
                            acts['ctrl-m']()
                        end
                    end,
                    ['ctrl-o'] = function()
                        forge_picker(kind, next_state, f)
                    end,
                    ['ctrl-r'] = function()
                        forge_mod.clear_list(cache_key)
                        forge_picker(kind, state, f)
                    end,
                },
            })
        end

        local cached = forge_mod.get_list(cache_key)
        if cached then
            open_pr_list(cached)
        else
            forge_mod.log_now('fetching PR list (' .. state .. ')...')
            vim.system(
                f:list_pr_json_cmd(state),
                { text = true },
                function(result)
                    vim.schedule(function()
                        local ok, prs =
                            pcall(vim.json.decode, result.stdout or '[]')
                        if ok and prs then
                            forge_mod.set_list(cache_key, prs)
                            open_pr_list(prs)
                        end
                    end)
                end
            )
        end
    else
        local issue_fields = f:issue_json_fields()
        local num_field = issue_fields.number

        local function open_issue_list(issues)
            table.sort(issues, function(a, b)
                return (a[num_field] or 0) > (b[num_field] or 0)
            end)
            local lines = {}
            for _, issue in ipairs(issues) do
                table.insert(lines, forge_mod.format_issue(issue, issue_fields))
            end
            require('fzf-lua').fzf_exec(lines, {
                prompt = ('%s (%s)> '):format(f.labels[kind], state),
                fzf_opts = {
                    ['--ansi'] = '',
                    ['--no-multi'] = '',
                    ['--header'] = make_header({
                        { 'ctrl-x', 'open in browser' },
                        { 'ctrl-o', 'toggle state' },
                        { 'ctrl-r', 'refresh' },
                    }),
                },
                actions = {
                    ['ctrl-x'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if num then
                            f:view_web(cli_kind, num)
                        end
                    end,
                    ['ctrl-o'] = function()
                        forge_picker(kind, next_state, f)
                    end,
                    ['ctrl-r'] = function()
                        forge_mod.clear_list(cache_key)
                        forge_picker(kind, state, f)
                    end,
                },
            })
        end

        local cached = forge_mod.get_list(cache_key)
        if cached then
            open_issue_list(cached)
        else
            forge_mod.log_now('fetching issue list (' .. state .. ')...')
            vim.system(
                f:list_issue_json_cmd(state),
                { text = true },
                function(result)
                    vim.schedule(function()
                        local ok, issues =
                            pcall(vim.json.decode, result.stdout or '[]')
                        if ok and issues then
                            forge_mod.set_list(cache_key, issues)
                            open_issue_list(issues)
                        end
                    end)
                end
            )
        end
    end
end

local function ci_picker(f, branch)
    require('lz.n').trigger_load('ibhagwan/fzf-lua')
    local forge_mod = require('forge')

    local function open_picker(runs)
        local normalized = {}
        for _, entry in ipairs(runs) do
            table.insert(normalized, f:normalize_run(entry))
        end

        local lines = {}
        for i, run in ipairs(normalized) do
            table.insert(lines, ('%d\t%s'):format(i, forge_mod.format_run(run)))
        end

        local function get_run(selected)
            if not selected[1] then return nil end
            local idx = tonumber(selected[1]:match('^(%d+)'))
            return idx and normalized[idx] or nil
        end

        require('fzf-lua').fzf_exec(lines, {
            prompt = ('%s (%s)> '):format(f.labels.ci, branch or 'all'),
            fzf_opts = {
                ['--ansi'] = '',
                ['--no-multi'] = '',
                ['--with-nth'] = '2..',
                ['--delimiter'] = '\t',
                ['--header'] = make_header({
                    { 'enter', 'view log' },
                    { 'ctrl-x', 'open in browser' },
                    { 'ctrl-r', 'refresh' },
                }),
            },
            actions = {
                ['default'] = function(selected)
                    local run = get_run(selected)
                    if not run then return end
                    forge_mod.log_now('fetching CI/CD logs...')
                    local s = run.status:lower()
                    local cmd
                    if s == 'in_progress' or s == 'running' or s == 'pending' or s == 'queued' then
                        cmd = f:run_tail_cmd(run.id)
                    elseif s == 'failure' or s == 'failed' then
                        cmd = f:run_log_cmd(run.id, true)
                    else
                        cmd = f:run_log_cmd(run.id, false)
                    end
                    vim.cmd('noautocmd botright new')
                    vim.fn.termopen(cmd)
                    vim.api.nvim_feedkeys(
                        vim.api.nvim_replace_termcodes('<C-\\><C-n>G', true, false, true),
                        'n', false
                    )
                    if run.url ~= '' then
                        vim.b.forge_run_url = run.url
                        vim.keymap.set('n', 'gx', function()
                            vim.ui.open(vim.b.forge_run_url)
                        end, { buffer = true, desc = 'open run in browser' })
                    end
                end,
                ['ctrl-x'] = function(selected)
                    local run = get_run(selected)
                    if run and run.url ~= '' then
                        vim.ui.open(run.url)
                    end
                end,
                ['ctrl-r'] = function()
                    ci_picker(f, branch)
                end,
            },
        })
    end

    if f.list_runs_json_cmd then
        forge_mod.log_now('fetching CI runs...')
        vim.system(
            f:list_runs_json_cmd(branch),
            { text = true },
            function(result)
                vim.schedule(function()
                    local ok, runs =
                        pcall(vim.json.decode, result.stdout or '[]')
                    if ok and runs and #runs > 0 then
                        open_picker(runs)
                    else
                        vim.notify(
                            '[forge]: no CI runs found',
                            vim.log.levels.INFO
                        )
                        vim.cmd.redraw()
                    end
                end)
            end
        )
    elseif f.list_runs_cmd then
        require('fzf-lua').fzf_exec(f:list_runs_cmd(branch), {
            prompt = f.labels.ci .. '> ',
            fzf_opts = { ['--ansi'] = '' },
        })
    end
end

git_picker = function()
    local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
    if vim.v.shell_error ~= 0 then
        vim.notify('[forge]: not a git repository', vim.log.levels.WARN)
        return
    end

    local forge_mod = require('forge')
    local f = forge_mod.detect()

    local loc = forge_mod.file_loc()
    local buf_name = vim.api.nvim_buf_get_name(0)
    local has_file = buf_name ~= ''
        and not buf_name:match('^fugitive://')
        and not buf_name:match('^term://')
        and not buf_name:match('^diffs://')
    local branch = vim.trim(vim.fn.system('git branch --show-current'))

    require('lz.n').trigger_load('ibhagwan/fzf-lua')

    local items = {}
    local actions = {}

    local function add(label, action)
        table.insert(items, label)
        actions[label] = action
    end

    if f then
        local pr_label = f.labels.pr_full
        local ci_label = f.labels.ci

        add(pr_label, function()
            forge_picker('pr', 'open', f)
        end)

        add('Issues', function()
            forge_picker('issue', 'all', f)
        end)

        add(ci_label, function()
            ci_picker(f, branch ~= '' and branch or nil)
        end)

        add('Browse Remote', function()
            f:browse_root()
        end)

        if has_file then
            add('Open File', function()
                if branch == '' then
                    vim.notify(
                        '[forge]: detached HEAD',
                        vim.log.levels.WARN
                    )
                    return
                end
                f:browse(loc, branch)
            end)

            add('Yank Commit URL', function()
                f:yank_commit(loc)
            end)

            add('Yank Branch URL', function()
                f:yank_branch(loc)
            end)
        end
    end

    add('Commits', function()
        local log_cmd =
            'git log --color --pretty=format:"%C(yellow)%h%Creset %Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset"'

        local hints = {
            { 'enter', 'checkout' },
            { 'ctrl-d', 'review diff' },
            { 'ctrl-y', 'copy hash' },
        }
        if f then
            table.insert(hints, 3, { 'ctrl-x', 'open in browser' })
        end

        require('fzf-lua').fzf_exec(log_cmd, {
            prompt = 'Commits> ',
            fzf_opts = {
                ['--ansi'] = '',
                ['--no-multi'] = '',
                ['--preview'] = 'git show --color {1}',
                ['--header'] = make_header(hints),
            },
            actions = {
                ['default'] = function(selected)
                    if not selected[1] then return end
                    local sha = selected[1]:match('%S+')
                    if not sha then return end
                    forge_mod.log_now('checking out ' .. sha .. '...')
                    vim.system(
                        { 'git', 'checkout', sha },
                        { text = true },
                        function(result)
                            vim.schedule(function()
                                if result.code == 0 then
                                    vim.notify(
                                        ('[forge]: checked out %s (detached)'):format(sha)
                                    )
                                else
                                    vim.notify(
                                        '[forge]: ' .. (result.stderr or 'checkout failed'),
                                        vim.log.levels.ERROR
                                    )
                                end
                                vim.cmd.redraw()
                            end)
                        end
                    )
                end,
                ['ctrl-d'] = function(selected)
                    if not selected[1] then return end
                    local sha = selected[1]:match('%S+')
                    if not sha then return end
                    local review = forge_mod.review
                    local range = sha .. '^..' .. sha
                    review.base = range
                    review.mode = 'unified'
                    require('diffs.commands').greview(range)
                    forge_mod.log_now('reviewing ' .. sha)
                end,
                ['ctrl-x'] = function(selected)
                    if not selected[1] then return end
                    local sha = selected[1]:match('%S+')
                    if sha and f then
                        f:browse_commit(sha)
                    end
                end,
                ['ctrl-y'] = function(selected)
                    if not selected[1] then return end
                    local sha = selected[1]:match('%S+')
                    if sha then
                        vim.fn.setreg('+', sha)
                        vim.notify('[forge]: copied ' .. sha)
                    end
                end,
            },
        })
    end)

    add('Branches', function()
        local branch_actions = {
            ['ctrl-d'] = function(selected)
                if not selected[1] then return end
                local br = selected[1]:match('%s-[%+%*]?%s+([^ ]+)')
                if not br then return end
                local review = forge_mod.review
                review.base = br
                review.mode = 'unified'
                require('diffs.commands').greview(br)
                forge_mod.log_now('reviewing ' .. br)
            end,
        }
        if f then
            branch_actions['ctrl-x'] = function(selected)
                if not selected[1] then return end
                local br = selected[1]:match('%s-[%+%*]?%s+([^ ]+)')
                if br then
                    f:browse_branch(br)
                end
            end
        end
        require('fzf-lua').git_branches({ actions = branch_actions })
    end)

    add('Worktrees', function()
        require('fzf-lua').git_worktrees()
    end)

    local prompt = f and (f.name:sub(1, 1):upper() .. f.name:sub(2)) .. '> '
        or 'Git> '

    require('fzf-lua').fzf_exec(items, {
        prompt = prompt,
        actions = {
            ['default'] = function(selected)
                if selected[1] and actions[selected[1]] then
                    actions[selected[1]]()
                end
            end,
        },
    })
end

vim.keymap.set({ 'n', 'v' }, '<c-g>', git_picker, { desc = 'forge git picker' })

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    callback = function()
        local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
        local items = info.loclist == 1 and vim.fn.getloclist(0)
            or vim.fn.getqflist()
        if #items == 0 then return end
        local bufname = vim.fn.bufname(items[1].bufnr)
        if not bufname:match('^diffs://') then return end
        vim.fn.matchadd('DiffAdd', [[\v\+\d+]])
        vim.fn.matchadd('DiffDelete', [[\v-\d+]])
        vim.fn.matchadd('DiffChange', [[\v\s\zsM\ze\s]])
        vim.fn.matchadd('diffAdded', [[\v\s\zsA\ze\s]])
        vim.fn.matchadd('DiffDelete', [[\v\s\zsD\ze\s]])
        vim.fn.matchadd('DiffText', [[\v\s\zsR\ze\s]])
    end,
})

local function close_review_view()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('^fugitive://') or name:match('^diffs://review:') then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    pcall(vim.cmd, 'diffoff!')
end

vim.keymap.set('n', ']q', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.cnext) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end, { desc = 'next quickfix entry' })

vim.keymap.set('n', '[q', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.cprev) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end, { desc = 'prev quickfix entry' })

vim.keymap.set('n', ']g', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.lnext) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end, { desc = 'next loclist entry' })

vim.keymap.set('n', '[g', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.lprev) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end, { desc = 'prev loclist entry' })

vim.keymap.set('n', 's', function()
    local review = require('forge').review
    if not review.base then
        vim.cmd('normal! s')
        return
    end
    if review.mode == 'unified' then
        local commands = require('diffs.commands')
        local file = commands.review_file_at_line(
            vim.api.nvim_get_current_buf(),
            vim.fn.line('.')
        )
        review.mode = 'split'
        if file then
            vim.cmd('edit ' .. vim.fn.fnameescape(file))
            pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
        end
    else
        local current_file = vim.fn.expand('%:.')
        close_review_view()
        review.mode = 'unified'
        require('diffs.commands').greview(review.base)
        if current_file ~= '' then
            vim.fn.search(
                'diff %-%-git a/' .. vim.pesc(current_file),
                'cw'
            )
        end
    end
end, { desc = 'toggle review split/unified' })
