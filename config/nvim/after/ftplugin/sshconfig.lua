local ssh = require('config.completion.ssh')

require('config.completion.filetype').setup(
    "v:lua.require'config.completion.ssh'.complete",
    ssh.preload
)
