vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
})

-- selene: allow(global_usage)
function _G._fugitive_stl()
    local s = vim.fn.FugitiveStatusline()
    return s ~= '' and s .. ' ' or ''
end

vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        vim.o.statusline = ' %{v:lua._fugitive_stl()}'
            .. vim.o.statusline:sub(2)
    end,
})

