local aug = vim.api.nvim_create_augroup('AAugs', { clear = true })

vim.api.nvim_create_autocmd('BufEnter', {
    command = 'setl formatoptions-=cro spelloptions=camel,noplainbuffer',
    group = aug,
})

vim.api.nvim_create_autocmd({ 'TermOpen', 'BufWinEnter' }, {
    callback = function(args)
        if vim.bo[args.buf].buftype == 'terminal' then
            vim.opt_local.number = false
            vim.opt_local.relativenumber = false
            vim.keymap.set('n', 'G', 'Gi', {
                buffer = args.buf,
                desc = 'jump to end, resume terminal',
            })
            vim.keymap.set('t', '<c-u>', [[<c-\><c-n><c-u>]], {
                buffer = args.buf,
                desc = 'scroll up half-page',
            })
            vim.cmd.startinsert()
        end
    end,
    group = aug,
})

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'fzf', 'TelescopePrompt', 'TelescopeResults' },
    callback = function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
    end,
    group = aug,
})

vim.api.nvim_create_autocmd('BufReadPost', {
    command = 'sil! normal g`"',
    group = aug,
})
vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function()
        vim.highlight.on_yank({ higroup = 'Visual', timeout = 300 })
    end,
    group = aug,
})

vim.api.nvim_create_autocmd({ 'FocusLost', 'BufLeave', 'VimLeave' }, {
    pattern = '*',
    callback = function()
        vim.cmd('silent! wall')
    end,
    group = aug,
})

vim.api.nvim_create_autocmd('WinEnter', {
    group = aug,
    callback = function()
        vim.wo.cursorline = true
    end,
})

vim.api.nvim_create_autocmd('WinLeave', {
    group = aug,
    callback = function()
        vim.wo.cursorline = false
    end,
})

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'lua', 'vim' },
    callback = function(ev)
        vim.keymap.set(
            'n',
            '<leader>x',
            ':.source<cr>',
            { buffer = ev.buf, desc = 'eval current line' }
        )
        vim.keymap.set(
            'x',
            '<leader>x',
            ':source<cr>',
            { buffer = ev.buf, desc = 'eval selection' }
        )
    end,
    group = aug,
})
