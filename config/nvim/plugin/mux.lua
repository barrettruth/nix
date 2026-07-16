vim.api.nvim_create_user_command('Mux', function(opts)
    require('mux.command').mux(opts.args)
end, { nargs = '?', complete = 'file' })
