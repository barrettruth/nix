vim.opt_local.number = true
vim.opt_local.relativenumber = true
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. '\nsetl nu< rnu<'
