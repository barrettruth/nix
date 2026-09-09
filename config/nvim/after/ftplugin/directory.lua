vim.opt_local.bufhidden = 'wipe'

vim.keymap.set('n', 'g.', function()
    vim.b.dir_git_visible = not vim.b.dir_git_visible
    vim.api.nvim_feedkeys(vim.keycode('<Plug>(nvim-dir-reload)'), 'm', false)
end, {
    buffer = true,
    desc = 'toggle git-visible entries',
})

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl bh<'
    .. '\nsil! nunmap <buffer> g.'
    .. '\nunlet! b:dir_git_visible'
