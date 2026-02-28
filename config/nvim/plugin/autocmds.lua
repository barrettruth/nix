local aug = vim.api.nvim_create_augroup('AAugs', { clear = true })

vim.api.nvim_create_autocmd('BufEnter', {
    command = 'setl formatoptions-=cro spelloptions=camel,noplainbuffer',
    group = aug,
})

vim.api.nvim_create_autocmd({ 'TermOpen', 'BufWinEnter' }, {
    callback = function(args)
        if vim.bo[args.buf].buftype == 'terminal' then
            vim.opt_local.number = true
            vim.opt_local.relativenumber = true
            vim.cmd.startinsert()
        end
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
