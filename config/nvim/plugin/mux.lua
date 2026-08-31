vim.api.nvim_create_user_command('Mux', function(opts)
    require('mux.command').mux(opts.args)
end, { nargs = '?', complete = 'file' })

vim.keymap.set({ 'n', 'i', 't' }, '<a-x>p', function()
    require('mux.fzf').pick()
end, { desc = 'mux: pick project', silent = true })
