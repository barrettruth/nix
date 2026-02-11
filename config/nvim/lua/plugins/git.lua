---@type string|nil
local prev_gitsigns_signcol = nil

return {
    {
        'tpope/vim-fugitive',
        cmd = { 'Git', 'G', 'Gread', 'Gwrite', 'Gdiffsplit', 'Gvdiffsplit' },
    },
    {
        dir = '~/dev/diffs.nvim',
        'barrettruth/diffs.nvim',
        init = function()
            vim.g.diffs = {
                debug = false,
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
            { '<leader>Go', '<cmd>lua Snacks.gitbrowse()<cr>' },
            { '<leader>Gi', '<cmd>lua Snacks.picker.gh_issue()<cr>' },
            { '<leader>Gp', '<cmd>lua Snacks.picker.gh_pr()<cr>' },
        },
    },
}
