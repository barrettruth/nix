local tmux = require('config.completion.tmux')

require('config.completion.filetype').setup(
    "v:lua.require'config.completion.tmux'.complete",
    tmux.preload
)
