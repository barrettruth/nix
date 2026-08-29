require('config.run').setup()

vim.keymap.set('n', '<c-r>', '<Plug>(run)', { remap = true })
vim.keymap.set('n', '<c-s-r>', '<Plug>(run-disable)', { remap = true })
