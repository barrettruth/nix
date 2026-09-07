vim.opt_local.colorcolumn = '73'
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\ncall v:lua.require("config.ftplugin").undo_window_options(["colorcolumn"])'
