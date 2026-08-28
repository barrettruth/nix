local defaults = { language = 'cpp' }

vim.g.cp = vim.tbl_deep_extend('force', defaults, vim.g.cp or {})

require('config.cp').setup()

vim.keymap.set('n', '<leader>r', '<Plug>(cp-run)', { remap = true })
vim.keymap.set('n', '<leader>d', '<Plug>(cp-debug)', { remap = true })
vim.keymap.set('n', '<leader>j', '<Plug>(cp-judge)', { remap = true })
vim.keymap.set('n', 'gX', '<Plug>(cp-problem)', { remap = true })
vim.keymap.set('n', 'gS', '<Plug>(cp-submit)', { remap = true })
