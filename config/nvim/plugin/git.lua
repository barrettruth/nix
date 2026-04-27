vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
})

-- selene: allow(global_usage)
vim.api.nvim_create_autocmd('User', {
    pattern = 'ForgeStatusUpdate',
    callback = function()
        vim.cmd.redrawstatus()
    end,
})
