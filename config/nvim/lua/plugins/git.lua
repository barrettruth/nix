---@return string
local function gh_file_loc()
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
local function gh_yank(args)
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

---@param kind 'issue'|'pr'
---@param state 'all'|'open'|'closed'
local function gh_picker(kind, state)
    local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
    local label = kind == 'pr' and 'PRs' or 'Issues'
    require('fzf-lua').fzf_exec(('gh %s list --limit 100 --state %s'):format(kind, state), {
        prompt = ('%s (%s)> '):format(label, state),
        header = ':: <c-o> to toggle all/open/closed',
        actions = {
            ['default'] = function(selected)
                local num = selected[1]:match('^(%d+)')
                if num then
                    vim.system({ 'gh', kind, 'view', num, '--web' })
                end
            end,
            ['ctrl-o'] = function()
                gh_picker(kind, next_state)
            end,
        },
    })
end

return {
    {
        'tpope/vim-fugitive',
        cmd = { 'Git', 'G', 'Gread', 'Gwrite', 'Gdiffsplit', 'Gvdiffsplit' },
    },
    {
        dir = '~/dev/diffs.nvim',
        enabled = true,
        dependencies = {
            'NeogitOrg/neogit',
            'sindrets/diffview.nvim',
        },
        init = function()
            vim.g.diffs = {
                fugitive = true,
                neogit = true,
                extra_filetypes = { 'diff' },
                hide_prefix = true,
                highlights = {
                    vim = {
                        enabled = true,
                    },
                    intra = {
                        enabled = false,
                        max_lines = 500,
                    },
                },
            }
        end,
    },
    {
        'NeogitOrg/neogit',
        dependencies = {
            'nvim-lua/plenary.nvim',
            'sindrets/diffview.nvim',
        },
        cmd = 'Neogit',
        opts = {
            integrations = {
                diffview = true,
            },
        },
    },
    {
        'sindrets/diffview.nvim',
        cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
    },
    {
        'ibhagwan/fzf-lua',
        keys = {
            {
                '<leader>go',
                function()
                    local branch = vim.trim(vim.fn.system('git branch --show-current'))
                    vim.system({ 'gh', 'browse', gh_file_loc(), '--branch', branch })
                end,
                mode = { 'n', 'v' },
            },
            {
                '<leader>gy',
                function()
                    gh_yank({ 'gh', 'browse', gh_file_loc(), '--commit=last', '-n' })
                end,
                mode = { 'n', 'v' },
            },
            {
                '<leader>gl',
                function()
                    gh_yank({ 'gh', 'browse', gh_file_loc(), '-n' })
                end,
                mode = { 'n', 'v' },
            },
            {
                '<leader>gx',
                function()
                    vim.system({ 'gh', 'browse' })
                end,
            },
            {
                '<leader>gi',
                function()
                    gh_picker('issue', 'all')
                end,
            },
            {
                '<leader>gp',
                function()
                    gh_picker('pr', 'all')
                end,
            },
        },
    },
}
