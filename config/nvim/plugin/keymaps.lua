vim.keymap.set('n', '<left>', '<cmd>vertical resize -10<cr>')
vim.keymap.set('n', '<right>', '<cmd>vertical resize +10<cr>')
vim.keymap.set('n', '<down>', '<cmd>resize +10<cr>')
vim.keymap.set('n', '<up>', '<cmd>resize -10<cr>')

vim.keymap.set('n', 'J', 'mzJ`z')

vim.keymap.set('x', 'p', '"_dp')
vim.keymap.set('x', 'P', '"_dP')
vim.keymap.set('t', '<esc>', '<c-\\><c-n>')
