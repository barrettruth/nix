vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
})

-- selene: allow(global_usage)
function _G._fugitive_stl()
    local s = vim.fn.FugitiveStatusline()
    return s ~= '' and s .. ' ' or ''
end

vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        vim.o.statusline = ' %{v:lua._fugitive_stl()}'
            .. vim.o.statusline:sub(2)
    end,
})

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    callback = function()
        vim.fn.matchadd('DiffAdd', [[\v\+\d+]])
        vim.fn.matchadd('DiffDelete', [[\v-\d+]])
        vim.fn.matchadd('DiffChange', [[\v\s\zsM\ze\s]])
        vim.fn.matchadd('diffAdded', [[\v\s\zsA\ze\s]])
        vim.fn.matchadd('DiffDelete', [[\v\s\zsD\ze\s]])
        vim.fn.matchadd('DiffText', [[\v\s\zsR\ze\s]])
    end,
})

---@param fn fun(f: forge.Forge)
---@return fun()
local function with_forge(fn)
    return function()
        local f = require('forge').detect()
        if not f then
            vim.notify('[forge.nvim]: no supported forge detected', vim.log.levels.WARN)
            return
        end
        fn(f)
    end
end

---@type { base: string?, mode: 'unified'|'split' }
local review = { base = nil, mode = 'unified' }

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
                ['--with-nth'] = '2..',
                ['--delimiter'] = '\t',
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
                    local bucket = (c.bucket or ''):lower()
                    local cmd
                    if bucket == 'pending' then
                        cmd = f:check_tail_cmd(run_id)
                    else
                        cmd = f:check_log_cmd(run_id, bucket == 'fail')
                    end
                    vim.cmd(
                        'botright split | terminal '
                            .. table.concat(cmd, ' ')
                    )
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
        forge_mod.log('fetching checks for PR #' .. num .. '...')
        vim.system(f:checks_json_cmd(num), { text = true }, function(result)
            vim.schedule(function()
                local ok, checks = pcall(vim.json.decode, result.stdout or '[]')
                if ok and checks then
                    open_picker(checks)
                else
                    vim.notify('[forge.nvim]: no checks found', vim.log.levels.INFO)
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
        local checkout = f.name == 'github' and { 'gh', 'pr', 'checkout', num }
            or f.name == 'gitlab' and { 'glab', 'mr', 'checkout', num }
            or { 'tea', 'pr', 'checkout', num }
        require('forge').log('checking out PR #' .. num .. '...')
        vim.system(checkout, { text = true }, function(result)
            vim.schedule(function()
                if result.code == 0 then
                    vim.notify(('[forge.nvim]: checked out PR #%s'):format(num))
                    vim.cmd.redraw()
                else
                    vim.notify(
                        '[forge.nvim]: ' .. (result.stderr or 'checkout failed'),
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
        local repo_root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
        local checkout_cmd = f.name == 'github'
                and { 'gh', 'pr', 'checkout', num }
            or f.name == 'gitlab' and { 'glab', 'mr', 'checkout', num }
            or { 'tea', 'pr', 'checkout', num }

        forge_mod.log('reviewing PR #' .. num .. '...')
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
            require('forge').log('approving PR #' .. num .. '...')
            vim.system(f:approve_cmd(num), { text = true }, function(result)
                vim.schedule(function()
                    if result.code == 0 then
                        vim.notify(('[forge.nvim]: approved PR #%s'):format(num))
                        vim.cmd.redraw()
                    else
                        vim.notify(
                            '[forge.nvim]: ' .. (result.stderr or 'approve failed'),
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
                    require('forge').log('merging PR #' .. num .. ' (' .. info.merge_methods[1] .. ')...')
                    vim.system(
                        f:merge_cmd(num, info.merge_methods[1]),
                        { text = true },
                        function(result)
                            vim.schedule(function()
                                if result.code == 0 then
                                    vim.notify(
                                        ('[forge.nvim]: merged PR #%s (%s)'):format(
                                            num,
                                            info.merge_methods[1]
                                        )
                                    )
                                    vim.cmd.redraw()
                                else
                                    vim.notify(
                                        '[forge.nvim]: ' .. (result.stderr or 'merge failed'),
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
                            require('forge').log('merging PR #' .. num .. ' (' .. method .. ')...')
                            vim.system(
                                f:merge_cmd(num, method),
                                { text = true },
                                function(result)
                                    vim.schedule(function()
                                        if result.code == 0 then
                                            vim.notify(
                                                ('[forge.nvim]: merged PR #%s (%s)'):format(
                                                    num,
                                                    method
                                                )
                                            )
                                            vim.cmd.redraw()
                                        else
                                            vim.notify(
                                                '[forge.nvim]: ' .. (result.stderr or 'merge failed'),
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
                fzf_opts = { ['--ansi'] = '' },
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
            forge_mod.log('fetching PR list (' .. state .. ')...')
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

        local function open_issue_list(issues)
            local lines = {}
            for _, issue in ipairs(issues) do
                table.insert(lines, forge_mod.format_issue(issue, issue_fields))
            end
            require('fzf-lua').fzf_exec(lines, {
                prompt = ('%s (%s)> '):format(f.labels[kind], state),
                fzf_opts = { ['--ansi'] = '' },
                actions = {
                    ['default'] = function(selected)
                        if not selected[1] then return end
                        local num = selected[1]:match('^[#!]?(%d+)')
                        if num then
                            f:view_web(cli_kind, num)
                        end
                    end,
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
            forge_mod.log('fetching issue list (' .. state .. ')...')
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

vim.keymap.set(
    { 'n', 'v' },
    '<leader>go',
    with_forge(function(f)
        local branch = vim.trim(vim.fn.system('git branch --show-current'))
        if branch == '' then
            vim.notify('[forge.nvim]: detached HEAD', vim.log.levels.WARN)
            return
        end
        f:browse(require('forge').file_loc(), branch)
    end)
)

vim.keymap.set(
    { 'n', 'v' },
    '<leader>gy',
    with_forge(function(f)
        f:yank_commit(require('forge').file_loc())
    end)
)

vim.keymap.set(
    { 'n', 'v' },
    '<leader>gl',
    with_forge(function(f)
        f:yank_branch(require('forge').file_loc())
    end)
)

vim.keymap.set(
    'n',
    '<leader>gx',
    with_forge(function(f)
        f:browse_root()
    end)
)


vim.keymap.set(
    'n',
    '<leader>gi',
    with_forge(function(f)
        forge_picker('issue', 'all', f)
    end)
)

vim.keymap.set(
    'n',
    '<leader>gp',
    with_forge(function(f)
        forge_picker('pr', 'open', f)
    end)
)

vim.keymap.set(
    'n',
    '<leader>gc',
    with_forge(function(f)
        require('lz.n').trigger_load('ibhagwan/fzf-lua')
        local branch = vim.trim(vim.fn.system('git branch --show-current'))
        if branch == '' then
            vim.notify('[forge.nvim]: detached HEAD, cannot find PR', vim.log.levels.WARN)
            return
        end
        require('forge').log('looking up PR for branch ' .. branch .. '...')
        vim.system(
            f:pr_for_branch_cmd(branch),
            { text = true },
            function(result)
                vim.schedule(function()
                    local num = vim.trim(result.stdout or '')
                    if num ~= '' and num:match('^%d+$') then
                        vim.notify('[forge.nvim]: found PR #' .. num .. ' for branch ' .. branch, vim.log.levels.INFO)
                        vim.cmd.redraw()
                        checks_picker(f, num)
                    else
                        vim.notify(
                            '[forge.nvim]: no PR found for branch ' .. branch,
                            vim.log.levels.WARN
                        )
                        vim.cmd.redraw()
                    end
                end)
            end
        )
    end)
)

vim.keymap.set('n', ']q', function()
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.cnext) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', '[q', function()
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.cprev) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', ']g', function()
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.lnext) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', '[g', function()
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.lprev) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', 's', function()
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
end)
