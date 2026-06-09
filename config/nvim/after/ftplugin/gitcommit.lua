require('config.completion.gitcommit').setup()

-- wipe on close so `:wq` unblocks a waiting `nvim --remote-wait` git editor
vim.bo.bufhidden = 'wipe'
