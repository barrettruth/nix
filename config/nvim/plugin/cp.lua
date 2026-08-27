local defaults = { language = 'cpp' }

vim.g.cp = vim.tbl_deep_extend('force', defaults, vim.g.cp or {})

require('config.cp').setup()
