local aug = vim.api.nvim_create_augroup('AAugs', { clear = true })

vim.api.nvim_create_autocmd('BufEnter', {
    command = 'setl formatoptions-=cro spelloptions=camel,noplainbuffer',
    group = aug,
})

vim.api.nvim_create_autocmd('TermOpen', {
    group = aug,
    callback = function(args)
        local normal = vim.b[args.buf].term_normal
        if not normal then
            vim.keymap.set('n', 'G', 'Gi', {
                buf = args.buf,
                desc = 'jump to end, resume terminal',
            })
        end
        vim.keymap.set('t', '<c-u>', [[<c-\><c-n><c-u>]], {
            buf = args.buf,
            desc = 'scroll up half-page',
        })
        if not normal then
            vim.cmd.startinsert()
        end
    end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
    command = 'sil! normal g`"',
    group = aug,
})
vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function()
        vim.hl.hl_op({ higroup = 'HighlightUndo', timeout = 300 })
    end,
    group = aug,
})

vim.api.nvim_create_autocmd('InsertEnter', {
    group = aug,
    callback = function()
        if vim.v.hlsearch == 1 then
            vim.schedule(function()
                vim.v.hlsearch = 0
            end)
        end
    end,
})

vim.api.nvim_create_autocmd('CursorMoved', {
    group = aug,
    callback = function()
        if vim.v.hlsearch == 0 then
            return
        end
        local count = vim.fn.searchcount({ recompute = true, maxcount = 0 })
        if count.exact_match ~= 1 then
            vim.schedule(function()
                vim.v.hlsearch = 0
            end)
        end
    end,
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
        if vim.bo.buftype == 'terminal' and not vim.b.term_normal then
            if vim.w.term_mode == 'nt' then
                vim.cmd.stopinsert()
            else
                vim.cmd.startinsert()
            end
        end
    end,
})

vim.api.nvim_create_autocmd('BufWinEnter', {
    group = aug,
    callback = vim.schedule_wrap(function()
        local cur = vim.api.nvim_get_current_win()
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_config(win).relative == '' then
                vim.wo[win][0].cursorline = win == cur
            end
        end
    end),
})

vim.api.nvim_create_autocmd('WinLeave', {
    group = aug,
    callback = function()
        vim.wo[0][0].cursorline = false
        if vim.bo.buftype == 'terminal' then
            vim.w.term_mode = vim.api.nvim_get_mode().mode
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
            { buf = ev.buf, desc = 'eval current line' }
        )
        vim.keymap.set(
            'x',
            '<leader>x',
            ':source<cr>',
            { buf = ev.buf, desc = 'eval selection' }
        )
    end,
    group = aug,
})

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'directory',
    callback = function(ev)
        vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = ev.buf })
    end,
})
