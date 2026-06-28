local dev_plugins = {
    'midnight.nvim',
    'diffs.nvim',
}

local opt_dir = vim.fn.stdpath('data') .. '/site/pack/dev/opt/'
vim.fn.mkdir(opt_dir, 'p')
for _, name in ipairs(dev_plugins) do
    local link = opt_dir .. name
    if not vim.uv.fs_lstat(link) then
        vim.uv.fs_symlink(vim.fn.expand('~/dev/' .. name), link)
    end
end

return {
    {
        'barrettruth/diffs.nvim',
        enabled = true,
        before = function()
            require('config.lz').load('barrettruth/midnight.nvim')

            vim.g.diffs = {
                debug = false,
                integrations = {
                    difftastic = false,
                    fugitive = true,
                },
                extra_filetypes = { 'diff' },
                view = { prefix = false },
                highlights = {
                    background = true,
                    vim = {
                        enabled = true,
                    },
                    intra = {
                        enabled = true,
                        algorithm = 'vscode',
                        max_lines = 500,
                    },
                },
                conflict = {
                    keymaps = {
                        ours = 'gto',
                        theirs = 'gtt',
                        both = 'gtb',
                        none = 'gt0',
                        next = ']x',
                        prev = '[x',
                    },
                },
            }
        end,
    },
    {
        'barrettruth/midnight.nvim',
        enabled = true,
        after = function()
            vim.cmd.colorscheme('midnight')
        end,
    },
}
