vim.keymap.set('n', '<leader>t', function()
    require('render').compile()
    vim.api.nvim_create_autocmd('User', {
        pattern = 'RenderCompileSuccess',
        once = true,
        callback = function(args)
            local pdf = args.data.output
            if not pdf or pdf == '' then
                return
            end
            if vim.fn.executable('sioyek') ~= 1 then
                return vim.notify('sioyek not found', vim.log.levels.ERROR)
            end
            vim.system({ 'sioyek', '--new-instance', pdf })
        end,
    })
end, { buffer = true })
