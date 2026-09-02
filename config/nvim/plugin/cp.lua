local defaults = {
    language = 'cpp',
    mappings = {
        run = '<leader>r',
        debug = '<leader>d',
        judge = '<leader>j',
        problem = 'gX',
        submit = 'gS',
    },
}

vim.g.cp = vim.tbl_deep_extend('force', defaults, vim.g.cp or {})

require('config.cp').setup()
