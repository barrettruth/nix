vim.opt.complete = { 'F', '.', 'w', 'b', 'o' }
vim.o.completefunc = "v:lua.require'config.completion'.complete"
vim.opt.completeopt = { 'menuone', 'popup' }

vim.o.autocomplete = false
vim.o.pumborder = 'single'
vim.o.pumheight = 15
