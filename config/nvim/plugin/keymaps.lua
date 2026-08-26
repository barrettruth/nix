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

for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
    vim.keymap.set(
        { 'n', 'i', 't' },
        '<a-x>' .. key,
        '<cmd>wincmd ' .. key .. '<cr>',
        { desc = 'go to window ' .. key }
    )
end
vim.keymap.set('n', 'J', 'mzJ`z', { desc = 'join lines (keep cursor)' })

vim.keymap.set('x', 'p', '"_dp', { desc = 'paste without yanking' })
vim.keymap.set('x', 'P', '"_dP', { desc = 'paste before without yanking' })
vim.keymap.set('x', 'x', '"_d', { desc = 'delete selection without yanking' })
vim.keymap.set('n', 'x', '"_x', { desc = 'delete char without yanking' })

vim.keymap.set('n', 'n', function()
    return vim.v.searchforward == 1 and 'n' or 'N'
end, { expr = true, desc = 'next match (always forward)' })
vim.keymap.set('n', 'N', function()
    return vim.v.searchforward == 1 and 'N' or 'n'
end, { expr = true, desc = 'prev match (always backward)' })

---@param boundaries boolean
local function highlight_cword(boundaries)
    local w = vim.fn.escape(vim.fn.expand('<cword>'), '/\\')
    local pat = boundaries and ([[\V\<]] .. w .. [[\>]]) or ([[\V]] .. w)
    vim.fn.setreg('/', pat)
    vim.fn.histadd('/', pat)
    vim.o.hlsearch = true
end
vim.keymap.set('n', '*', function()
    highlight_cword(true)
end, { desc = '* highlight cword, stay put' })
vim.keymap.set('n', 'g*', function()
    highlight_cword(false)
end, { desc = 'g* highlight cword without boundaries, stay put' })

vim.keymap.set('x', 'I', function()
    return vim.fn.mode():match('[vV]') and '<C-v>^o^I' or 'I'
end, { expr = true, desc = 'niceblock I' })
vim.keymap.set('x', 'A', function()
    return vim.fn.mode():match('[vV]') and '<C-v>0o$A' or 'A'
end, { expr = true, desc = 'niceblock A' })

vim.keymap.set(
    'n',
    'gV',
    '`[v`]',
    { desc = 'reselect last inserted/changed text' }
)

vim.keymap.set('n', 'g:', ':lua =', { desc = 'eval a Lua expression' })

vim.keymap.set('n', '<leader>iw', function()
    vim.wo.wrap = not vim.wo.wrap
end, { desc = 'toggle wrap' })
vim.keymap.set('n', '<leader>ic', function()
    vim.o.cmdheight = vim.o.cmdheight == 0 and 1 or 0
end, { desc = 'toggle cmdheight' })
vim.keymap.set('n', '<leader>i<space>', function()
    if vim.opt.diffopt:get().iwhiteall then
        vim.cmd('set diffopt-=iwhiteall')
    else
        vim.cmd('set diffopt+=iwhiteall')
    end
end, { desc = 'toggle diff whitespace' })
vim.keymap.set('n', '<leader>ii', function()
    local inline = vim.opt.diffopt:get().inline == 'none' and 'char' or 'none'
    vim.cmd('set diffopt+=inline:' .. inline)
end, { desc = 'toggle intra-line diff highlighting' })

if vim.fn.has('mac') == 1 then
    vim.keymap.set(
        'x',
        '<d-c>',
        '"+y',
        { desc = 'yank selection to clipboard' }
    )
    vim.keymap.set('n', '<d-v>', '"+p', { desc = 'paste clipboard' })
    vim.keymap.set('i', '<d-v>', '<c-r><c-o>+', { desc = 'paste clipboard' })
    vim.keymap.set('c', '<d-v>', '<c-r>+', { desc = 'paste clipboard' })
    vim.keymap.set('t', '<d-v>', '<c-\\><c-n>"+pa', {
        desc = 'paste clipboard',
    })
end
