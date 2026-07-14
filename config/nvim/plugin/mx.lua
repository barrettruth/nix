vim.api.nvim_create_user_command('Mx', function(opts)
    require('mx.command').mux(opts.args)
end, { nargs = '?' })
