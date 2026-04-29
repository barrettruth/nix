local ghostty = require('config.completion.ghostty')

vim.opt_local.complete = { '.', 'w', 'b' }
vim.bo.omnifunc = "v:lua.require'config.completion.ghostty'.complete"

ghostty.preload()
