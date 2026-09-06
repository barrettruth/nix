local autoread = require('nvim.autoread')

local source = {
    get_path = function(bufnr)
        local path = vim.fn.FugitiveWorkTree(bufnr)
        return path ~= '' and path or nil
    end,
    on_change = function(bufnr)
        vim.fn.FugitiveDidChange(bufnr)
    end,
    watch = function(path, callback)
        return vim._watch.watch(path, {
            uvflags = { recursive = true },
        }, callback)
    end,
}

vim.api.nvim_create_autocmd('User', {
    pattern = 'FugitiveIndex',
    group = vim.api.nvim_create_augroup('FugitiveAutoread', { clear = true }),
    callback = function(ev)
        autoread.register(ev.buf, source)
    end,
})
