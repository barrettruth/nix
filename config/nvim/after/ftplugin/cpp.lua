vim.opt.indentkeys:remove(':')
vim.opt_local.iskeyword:append(':')
require('config.cppreference').setup()

if vim.bo.buftype ~= '' or vim.fn.expand('%:t:r') == '' then
    return
end

vim.g.compiler_gcc_ignore_unmatched_lines = true
vim.cmd.compiler('gcc')

local binary = vim.fn.shellescape(
    vim.fs.joinpath(
        vim.fn.fnamemodify(vim.fn.tempname(), ':h'),
        vim.fn.expand('%:t:r')
    )
)

vim.bo.makeprg = table.concat({
    'c++',
    '-std=c++23',
    '-Wall',
    '-Wextra',
    '-g',
    '-fdiagnostics-color=never',
    '-o',
    binary,
    '%:S',
}, ' ')
local run = type(vim.b.run) == 'table' and vim.b.run or {}
run.command = binary
vim.b.run = run
