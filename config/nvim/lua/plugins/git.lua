return {
    {
        'tpope/vim-fugitive',
        cmd = { 'Git', 'G', 'Gread', 'Gwrite', 'Gdiffsplit', 'Gvdiffsplit' },
    },
    {
        dir = '~/dev/diffs.nvim',
        'barrettruth/diffs.nvim',
        enabled = true,
        init = function()
            vim.g.diffs = {
                debug = true,
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
        -- TODO: find out a way to remove this/better overall github integration
        'folke/snacks.nvim',
        ---@type snacks.Config
        opts = { gitbrowse = {} },
        keys = {
            { '<leader>go', '<cmd>lua Snacks.gitbrowse()<cr>' },
            { '<leader>gi', '<cmd>lua Snacks.picker.gh_issue()<cr>' },
            { '<leader>gp', '<cmd>lua Snacks.picker.gh_pr()<cr>' },
        },
    },
}
