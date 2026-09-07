vim.keymap.set('n', '<leader>x', ':.source<cr>', {
    buffer = true,
    desc = 'eval current line',
})
vim.keymap.set('x', '<leader>x', ':source<cr>', {
    buffer = true,
    desc = 'eval selection',
})
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsil! nunmap <buffer> <leader>x|sil! xunmap <buffer> <leader>x'
