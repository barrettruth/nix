local tmux = require('config.completion.tmux')

vim.opt_local.complete = { 'o', '.', 'w', 'b' }
vim.bo.omnifunc = "v:lua.require'config.completion.tmux'.complete"

tmux.preload()
