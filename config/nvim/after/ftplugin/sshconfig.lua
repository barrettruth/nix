local ssh = require('config.completion.ssh')

vim.opt_local.complete = { '.', 'w', 'b' }
vim.bo.omnifunc = "v:lua.require'config.completion.ssh'.complete"

ssh.preload()
