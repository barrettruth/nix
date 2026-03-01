vim.o.conceallevel = 1
vim.o.textwidth = 80

local buf = vim.api.nvim_get_current_buf()
local opened = false

vim.api.nvim_create_autocmd('User', {
    pattern = 'RenderCompileSuccess',
    callback = function(args)
        if args.data.bufnr ~= buf then
            return
        end
        local html = args.data.output
        if not opened and html and html ~= '' then
            opened = true
            vim.system({ 'xdg-open', html })
        end
    end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
    buffer = buf,
    callback = function()
        local ok, render = pcall(require, 'render')
        if ok then
            render.compile(buf)
        end
    end,
})

vim.keymap.set('n', '<leader>t', function()
    require('render').compile(buf)
end, { buffer = true })
