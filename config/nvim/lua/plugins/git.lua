vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
    { src = 'https://github.com/lewis6991/gitsigns.nvim', load = false },
})

---@return string
local function file_loc()
    local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
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

---@param args string[]
local function yank_url(args)
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

local function remote_web_url()
    local url = vim.trim(vim.fn.system('git remote get-url origin'))
    url = url:gsub('%.git$', '')
    url = url:gsub('^ssh://git@', 'https://')
    url = url:gsub('^git@([^:]+):', 'https://%1/')
    return url
end

local function gitlab_file_url(loc, ref)
    local base = remote_web_url()
    local file, lines = loc:match('^(.+):(.+)$')
    return ('%s/-/blob/%s/%s#L%s'):format(base, ref, file, lines)
end

local function detect_forge()
    local url = vim.trim(vim.fn.system('git remote get-url origin'))
    if vim.v.shell_error ~= 0 then
        return nil
    end
    if url:find('github') and vim.fn.executable('gh') == 1 then
        return 'github'
    end
    if url:find('gitlab') and vim.fn.executable('glab') == 1 then
        return 'gitlab'
    end
    return nil
end

local forges = {
    github = {
        kinds = { issue = 'issue', pr = 'pr' },
        labels = { issue = 'Issues', pr = 'PRs' },
        list_cmd = function(kind, state)
            return ('gh %s list --limit 100 --state %s'):format(kind, state)
        end,
        view_cmd = function(kind, num)
            return { 'gh', kind, 'view', num, '--web' }
        end,
        browse = function(loc, branch)
            vim.system({ 'gh', 'browse', loc, '--branch', branch })
        end,
        browse_root = function()
            vim.system({ 'gh', 'browse' })
        end,
        yank_branch = function(loc)
            yank_url({ 'gh', 'browse', loc, '-n' })
        end,
        yank_commit = function(loc)
            yank_url({ 'gh', 'browse', loc, '--commit=last', '-n' })
        end,
    },
    gitlab = {
        kinds = { issue = 'issue', pr = 'mr' },
        labels = { issue = 'Issues', pr = 'MRs' },
        list_cmd = function(kind, state)
            local cmd = ('glab %s list --per-page 100'):format(kind)
            if state == 'closed' then
                cmd = cmd .. ' --closed'
            elseif state == 'all' then
                cmd = cmd .. ' --all'
            end
            return cmd
        end,
        view_cmd = function(kind, num)
            return { 'glab', kind, 'view', num, '--web' }
        end,
        browse = function(loc, branch)
            vim.ui.open(gitlab_file_url(loc, branch))
        end,
        browse_root = function()
            vim.system({ 'glab', 'repo', 'view', '--web' })
        end,
        yank_branch = function(loc)
            local branch = vim.trim(vim.fn.system('git branch --show-current'))
            vim.fn.setreg('+', gitlab_file_url(loc, branch))
        end,
        yank_commit = function(loc)
            local commit = vim.trim(vim.fn.system('git rev-parse HEAD'))
            vim.fn.setreg('+', gitlab_file_url(loc, commit))
        end,
    },
}

---@param kind 'issue'|'pr'
---@param state 'all'|'open'|'closed'
local function forge_picker(kind, state)
    local forge_name = detect_forge()
    if not forge_name then
        vim.notify('No supported forge detected', vim.log.levels.WARN)
        return
    end
    local forge = forges[forge_name]
    local cli_kind = forge.kinds[kind]
    local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
    pcall(vim.cmd.packadd, 'fzf-lua')
    require('fzf-lua').fzf_exec(forge.list_cmd(cli_kind, state), {
        prompt = ('%s (%s)> '):format(forge.labels[kind], state),
        header = ':: <c-o> to toggle all/open/closed',
        actions = {
            ['default'] = function(selected)
                local num = selected[1]:match('^[#!]?(%d+)')
                if num then
                    vim.system(forge.view_cmd(cli_kind, num))
                end
            end,
            ['ctrl-o'] = function()
                forge_picker(kind, next_state)
            end,
        },
    })
end

local function with_forge(fn)
    return function()
        local forge_name = detect_forge()
        if not forge_name then
            vim.notify('No supported forge detected', vim.log.levels.WARN)
            return
        end
        fn(forges[forge_name])
    end
end

map({
    { 'n', 'v' },
    '<leader>go',
    with_forge(function(forge)
        local branch = vim.trim(vim.fn.system('git branch --show-current'))
        forge.browse(file_loc(), branch)
    end),
})
map({
    { 'n', 'v' },
    '<leader>gy',
    with_forge(function(forge)
        forge.yank_commit(file_loc())
    end),
})
map({
    { 'n', 'v' },
    '<leader>gl',
    with_forge(function(forge)
        forge.yank_branch(file_loc())
    end),
})
map({
    'n',
    '<leader>gx',
    with_forge(function(forge)
        forge.browse_root()
    end),
})
map({
    'n',
    '<leader>gd',
    function()
        pcall(vim.cmd.packadd, 'fzf-lua')
        require('fzf-lua').fzf_exec(
            'git branch -a --format="%(refname:short)"',
            {
                prompt = 'Git diff> ',
                actions = {
                    ['default'] = function(selected)
                        vim.cmd('Git diff ' .. selected[1])
                    end,
                },
            }
        )
    end,
})
map({
    'n',
    '<leader>gi',
    function()
        forge_picker('issue', 'all')
    end,
})
map({
    'n',
    '<leader>gp',
    function()
        forge_picker('pr', 'all')
    end,
})

return {
    {
        'tpope/vim-fugitive',
        cmd = { 'Git', 'G', 'Gread', 'Gwrite', 'Gdiffsplit', 'Gvdiffsplit' },
        after = function()
            vim.o.statusline = '%{FugitiveStatusline()} ' .. vim.o.statusline
        end,
    },
    {
        'barrettruth/diffs.nvim',
        before = function()
            vim.g.diffs = {
                fugitive = true,
                neogit = false,
                extra_filetypes = { 'diff' },
                hide_prefix = true,
                highlights = {
                    vim = {
                        enabled = true,
                    },
                    intra = {
                        enabled = true,
                        max_lines = 500,
                    },
                },
            }
        end,
    },
    {
        'lewis6991/gitsigns.nvim',
        enabled = false,
        event = 'DeferredUIEnter',
        after = function()
            require('gitsigns').setup({
                signs = {
                    add = { text = '│' },
                    change = { text = '│' },
                    delete = { text = '＿' },
                    topdelete = { text = '‾' },
                    changedelete = { text = '│' },
                },
            })
        end,
        keys = {
            { ']g', '<cmd>Gitsigns next_hunk<cr>' },
            { '[g', '<cmd>Gitsigns prev_hunk<cr>' },
            { '<leader>gB', '<cmd>Gitsigns toggle_current_line_blame<cr>' },
        },
    },
}
