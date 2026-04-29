local ghostty = require('config.completion.ghostty')

vim.bo.omnifunc = "v:lua.require'config.completion.ghostty'.complete"

ghostty.preload()
