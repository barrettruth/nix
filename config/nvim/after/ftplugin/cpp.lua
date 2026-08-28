vim.opt.indentkeys:remove(':')

if vim.bo.buftype ~= '' or vim.fn.expand('%:t:r') == '' then
    return
end

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
vim.b.run = binary
