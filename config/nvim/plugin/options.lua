vim.o.autoread = true
vim.o.autowrite = true

vim.o.breakindent = true

vim.o.cursorline = true

vim.opt.diffopt:append('linematch:60')

vim.o.expandtab = true

vim.o.exrc = true
vim.o.secure = true

vim.o.foldcolumn = 'auto'
vim.o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
vim.o.foldlevel = 99
vim.o.foldmethod = 'expr'
vim.o.foldtext = ''

vim.opt.fillchars = {
    eob = ' ',
    vert = '│',
    diff = '╱',
    foldopen = 'v',
    foldclose = '>',
    foldsep = ' ',
    foldinner = ' ',
}

vim.opt.iskeyword:append('-')

vim.o.laststatus = 3

vim.o.linebreak = true

vim.o.list = true
vim.opt.listchars = {
    space = ' ',
    trail = '·',
}

vim.opt.matchpairs:append('<:>')

vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = 'no'

vim.o.statuscolumn = '%s%C %=%{v:relnum?v:relnum:v:lnum} '
vim.o.statusline = " %{len(expand('%'))?expand('%:~').' ':''}%h%m%r%=%c:%l/%L "

vim.opt.path:append('**')

vim.o.scrolloff = 8

vim.o.shiftwidth = 2

vim.opt.shortmess:append('acCIs')

vim.o.spellfile = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. '/.local/share'))
    .. '/nvim/spell.encoding.add'

vim.o.splitkeep = 'screen'

vim.o.splitbelow = true
vim.o.splitright = true

vim.o.swapfile = false

vim.o.termguicolors = true

vim.o.undodir = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. '/.local/share'))
    .. '/nvim/undo'
vim.o.undofile = true

vim.o.updatetime = 50

vim.o.winborder = 'single'

vim.o.wrap = false
