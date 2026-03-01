local o, opt = vim.o, vim.opt

o.autoread = true
o.autowrite = true

o.breakindent = true

o.cursorline = true

opt.diffopt:append('linematch:60')

o.expandtab = true

o.exrc = true
o.secure = true

o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
o.foldlevel = 99
o.foldmethod = 'expr'
o.foldtext = ''

opt.fillchars = {
    eob = ' ',
    vert = '│',
    diff = '╱',
    foldopen = 'v',
    foldclose = '>',
    foldsep = ' ',
    foldinner = ' ',
}

opt.iskeyword:append('-')

o.laststatus = 3

o.linebreak = true

o.list = true
opt.listchars = {
    space = ' ',
    trail = '·',
}

opt.matchpairs:append('<:>')

o.number = true
o.relativenumber = true
o.signcolumn = 'no'
o.statuscolumn = '%s%C %=%{v:relnum?v:relnum:v:lnum} '

opt.path:append('**')

o.scrolloff = 8

o.shiftwidth = 2

opt.shortmess:append('acCIs')

o.showtabline = 0

o.spellfile = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. '/.local/share'))
    .. '/nvim/spell.encoding.add'

o.splitkeep = 'screen'

o.splitbelow = true
o.splitright = true

o.swapfile = false

o.termguicolors = true

o.undodir = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. '/.local/share'))
    .. '/nvim/undo'
o.undofile = true

o.updatetime = 50

o.winborder = 'single'
o.winbar = ''

o.wrap = false
