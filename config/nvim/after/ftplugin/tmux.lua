local tmux = require('config.completion.tmux')

vim.bo.omnifunc = "v:lua.require'config.completion.tmux'.complete"

tmux.preload()
