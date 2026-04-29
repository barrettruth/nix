local ghostty = require('config.completion.ghostty')

require('config.completion.filetype').setup(
    "v:lua.require'config.completion.ghostty'.complete",
    ghostty.preload
)
