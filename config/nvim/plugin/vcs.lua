vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
    'https://github.com/lewis6991/gitsigns.nvim',
    'https://github.com/justinmk/vim-ug',
})

require('gitsigns').setup({
    signcolumn = false,
    signs_staged_enable = false,
    current_line_blame = false,
    on_attach = function(buf)
        vim.keymap.set('n', 'Un', function()
            require('gitsigns').blame_line({ full = true })
        end, { buffer = buf, desc = 'preview line blame' })
    end,
})

vim.pack.add({
    'https://github.com/justinmk/guh.nvim',
}, { load = function() end })

require('lz.n').load({
    {
        'justinmk/guh.nvim',
        cmd = { 'Guh', 'GuhComment' },
        keys = {
            { '<leader>gg', '<cmd>Guh<cr>', desc = 'guh repo' },
            { '<leader>go', '<cmd>Guh .<cr>', desc = 'guh open target' },
            { '<leader>gr', '<Plug>(guh-review)', desc = 'guh review pr' },
            { '<leader>gt', '<Plug>(guh-logs)', desc = 'guh pr logs' },
        },
    },
})

vim.api.nvim_create_user_command('Stack', function()
    require('stack').list()
end, { desc = 'list the stack holding the current pull request' })

-- ]s and [s are the builtin spell motions, so they stay buffer-local to guh.
vim.api.nvim_create_autocmd('BufEnter', {
    group = vim.api.nvim_create_augroup('stack', {}),
    callback = function(ev)
        if not vim.api.nvim_buf_get_name(ev.buf):match('^guh://') then
            return
        end
        vim.keymap.set('n', ']s', function()
            require('stack').walk(1)
        end, { buffer = ev.buf, desc = 'next pull request in stack' })
        vim.keymap.set('n', '[s', function()
            require('stack').walk(-1)
        end, { buffer = ev.buf, desc = 'previous pull request in stack' })
    end,
})
