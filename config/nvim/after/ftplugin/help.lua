vim.opt_local.number = true
vim.opt_local.conceallevel = 0
vim.opt_local.relativenumber = true
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl nu< cole< rnu< | sil! nunmap <buffer> q'

vim.keymap.set('n', 'q', vim.cmd.helpclose, { buf = 0, desc = 'close help' })
