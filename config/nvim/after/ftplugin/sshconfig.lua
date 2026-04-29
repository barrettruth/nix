local ssh = require('config.completion.ssh')

vim.bo.omnifunc = "v:lua.require'config.completion.ssh'.complete"

ssh.preload()
