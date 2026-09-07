vim.opt_local.number = true
vim.opt_local.relativenumber = true
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl et< ts< sts< sw< isk< tfu<'
    .. '\ncall v:lua.require("config.ftplugin").undo_window_options(["wrap", "breakindent", "linebreak", "colorcolumn", "list", "number", "relativenumber", "foldcolumn", "signcolumn", "foldenable", "foldmethod", "foldnestmax"])'
    .. '\nsil! nunmap <buffer> j|sil! nunmap <buffer> k|sil! nunmap <buffer> gO|sil! nunmap <buffer> <2-LeftMouse>|sil! nunmap <buffer> q'
