vim.keymap.set(
    'n',
    '<left>',
    '<cmd>vertical resize -10<cr>',
    { desc = 'shrink window width' }
)
vim.keymap.set(
    'n',
    '<right>',
    '<cmd>vertical resize +10<cr>',
    { desc = 'grow window width' }
)
vim.keymap.set(
    'n',
    '<down>',
    '<cmd>resize +10<cr>',
    { desc = 'grow window height' }
)
vim.keymap.set(
    'n',
    '<up>',
    '<cmd>resize -10<cr>',
    { desc = 'shrink window height' }
)

vim.keymap.set('n', 'J', 'mzJ`z', { desc = 'join lines (keep cursor)' })

vim.keymap.set('x', 'p', '"_dp', { desc = 'paste without yanking' })
vim.keymap.set('x', 'P', '"_dP', { desc = 'paste before without yanking' })
vim.keymap.set('t', '<esc>', '<c-\\><c-n>', { desc = 'exit terminal mode' })
