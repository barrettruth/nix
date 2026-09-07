vim.opt_local.conceallevel = 1
vim.opt_local.textwidth = 80
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. '\nsetl cole< tw<'
