local aug = vim.api.nvim_create_augroup('AAugs', { clear = true })

local tail_pending = {}

vim.api.nvim_create_autocmd('BufEnter', {
    command = 'setl formatoptions-=cro spelloptions=camel,noplainbuffer',
    group = aug,
})

vim.api.nvim_create_autocmd('TermOpen', {
    group = aug,
    callback = function(args)
        local normal = vim.b[args.buf].term_normal
        vim.b[args.buf].term_insert = not normal
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
        vim.api.nvim_buf_attach(args.buf, false, {
            on_lines = function(_, b)
                if not vim.api.nvim_buf_is_valid(b) then
                    return true
                end
                if tail_pending[b] then
                    return
                end
                tail_pending[b] = true
                vim.schedule(function()
                    tail_pending[b] = nil
                    if not vim.api.nvim_buf_is_valid(b) then
                        return
                    end
                    local cur = vim.api.nvim_get_current_win()
                    local last = vim.api.nvim_buf_line_count(b)
                    for _, w in ipairs(vim.fn.win_findbuf(b)) do
                        if w ~= cur and vim.api.nvim_win_is_valid(w) then
                            pcall(vim.api.nvim_win_set_cursor, w, { last, 0 })
                        end
                    end
                end)
            end,
        })
        if not normal then
            vim.cmd.startinsert()
        end
    end,
})

vim.api.nvim_create_autocmd('TermEnter', {
    group = aug,
    callback = function()
        if not vim.b.term_normal then
            vim.b.term_insert = true
        end
    end,
})

vim.api.nvim_create_autocmd('TermLeave', {
    group = aug,
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        if vim.b[buf].term_normal then
            vim.b[buf].term_insert = false
            return
        end
        if vim.b[buf].term_programmatic then
            vim.b[buf].term_programmatic = false
            return
        end
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
        vim.hl.hl_op({ higroup = 'HighlightUndo', timeout = 300 })
    end,
    group = aug,
})

vim.api.nvim_create_autocmd('InsertEnter', {
    group = aug,
    callback = function()
        if vim.v.hlsearch == 1 then
            vim.o.hlsearch = false
        end
    end,
})

vim.api.nvim_create_autocmd('CursorMoved', {
    group = aug,
    callback = function()
        if vim.v.hlsearch == 0 then
            return
        end
        local count = vim.fn.searchcount({ recompute = true, maxcount = 1 })
        if count.exact_match ~= 1 then
            vim.o.hlsearch = false
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
        if
            vim.bo.buftype == 'terminal'
            and not vim.b.term_normal
            and vim.b.term_insert
        then
            vim.cmd.startinsert()
        end
    end,
})

vim.api.nvim_create_autocmd('UIEnter', {
    group = aug,
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        if
            vim.bo[buf].buftype == 'terminal'
            and not vim.b[buf].term_normal
            and vim.b[buf].term_insert
        then
            vim.schedule(function()
                if
                    vim.api.nvim_get_current_buf() == buf
                    and not vim.b[buf].term_normal
                    and vim.b[buf].term_insert
                then
                    vim.cmd.startinsert()
                end
            end)
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
        if vim.bo.buftype == 'terminal' and not vim.b.term_normal then
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

vim.api.nvim_create_autocmd('VimResized', {
    group = aug,
    command = 'wincmd =',
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
