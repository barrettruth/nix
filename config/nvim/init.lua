vim.g.mapleader = ' '

vim.g.lz_n = {
    load = function(name)
        vim.cmd.packadd((name:match('[^/]+$') or name))
    end,
}

vim.pack.add({
    'https://github.com/lumen-oss/lz.n',
})

require('lz.n').load('plugins')
