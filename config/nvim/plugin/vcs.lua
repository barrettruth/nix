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
