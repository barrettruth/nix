vim.opt_local.conceallevel = 1
vim.opt_local.textwidth = 80
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl tw<'
    .. '\ncall v:lua.require("config.ftplugin").undo_window_options(["conceallevel", "foldexpr", "foldmethod", "foldtext"])'
    .. '\nunl! b:html_omni_flavor b:yaml_schema'
