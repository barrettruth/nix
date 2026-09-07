vim.opt_local.bufhidden = 'wipe'
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. '\nsetl bh<'
