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

-- ctrl+shift+hjkl: distinct from <c-hjkl> under the kitty protocol, so it leaves
-- <c-l> clear / <c-k> kill-line / <bs> / <cr> alone and isn't claimed elsewhere.
for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
    vim.keymap.set(
        'n',
        '<c-s-' .. key .. '>',
        '<c-w>' .. key,
        { desc = 'go to window ' .. key }
    )
    vim.keymap.set(
        't',
        '<c-s-' .. key .. '>',
        [[<c-\><c-n><c-w>]] .. key,
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
