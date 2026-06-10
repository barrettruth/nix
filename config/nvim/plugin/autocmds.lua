local aug = vim.api.nvim_create_augroup('AAugs', { clear = true })

vim.api.nvim_create_autocmd('BufEnter', {
    command = 'setl formatoptions-=cro spelloptions=camel,noplainbuffer',
    group = aug,
})

vim.api.nvim_create_autocmd('TermOpen', {
    group = aug,
    callback = function(args)
        vim.b[args.buf].term_insert = true
        vim.keymap.set('n', 'G', 'Gi', {
            buffer = args.buf,
            desc = 'jump to end, resume terminal',
        })
        vim.keymap.set('t', '<c-u>', [[<c-\><c-n><c-u>]], {
            buffer = args.buf,
            desc = 'scroll up half-page',
        })
        vim.cmd.startinsert()
    end,
})

vim.api.nvim_create_autocmd('TermEnter', {
    group = aug,
    callback = function()
        vim.b.term_insert = true
    end,
})

vim.api.nvim_create_autocmd('TermLeave', {
    group = aug,
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        vim.b[buf].term_insert = false
        vim.b[buf].term_leaving = true
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) then
                vim.b[buf].term_leaving = false
            end
        end)
    end,
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
        vim.wo[0][0].cursorline = true
        if vim.bo.buftype == 'terminal' and vim.b.term_insert then
            vim.cmd.startinsert()
        end
    end,
})

vim.api.nvim_create_autocmd('WinLeave', {
    group = aug,
    callback = function()
        vim.wo[0][0].cursorline = false
        if vim.bo.buftype == 'terminal' then
            if vim.b.term_leaving then
                vim.b.term_insert = true
            end
            if vim.b.term_insert then
                pcall(
                    vim.api.nvim_win_set_cursor,
                    0,
                    { vim.api.nvim_buf_line_count(0), 0 }
                )
            end
        end
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
