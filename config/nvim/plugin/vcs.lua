vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
    'https://github.com/lewis6991/gitsigns.nvim',
})

require('gitsigns').setup({
    signcolumn = false,
    signs_staged_enable = false,
    current_line_blame = false,
})

vim.keymap.set('n', '<leader>ig', function()
    require('config.statuscolumn').toggle_git()
end, { desc = 'toggle git signs' })

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
