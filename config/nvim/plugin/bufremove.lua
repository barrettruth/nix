vim.keymap.set(
    'n',
    '<leader>bd',
    '<cmd>bdelete<cr>',
    { desc = 'delete buffer' }
)
vim.keymap.set(
    'n',
    '<leader>bw',
    '<cmd>bwipeout<cr>',
    { desc = 'wipeout buffer' }
)
vim.keymap.set('n', '<c-w>x', '<cmd>bdelete<cr>', { desc = 'delete buffer' })
