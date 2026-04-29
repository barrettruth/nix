vim.opt_local.complete = { 'o', '.', 'w', 'b' }
vim.bo.omnifunc =
    "v:lua.require'config.completion.conventional_commits'.omnifunc"
