vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
})

-- Redraw the statusline when forge.nvim reports a branch/PR status change.
-- selene: allow(global_usage)
vim.api.nvim_create_autocmd('User', {
    pattern = 'ForgeStatusUpdate',
    callback = function()
        vim.cmd.redrawstatus()
    end,
})
