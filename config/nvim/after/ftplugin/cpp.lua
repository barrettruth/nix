vim.opt_local.indentkeys:remove(':')
vim.opt_local.iskeyword:append(':')
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. '\nsetl indk< isk<'

if vim.bo.buftype ~= '' or vim.fn.expand('%:t:r') == '' then
    return
end

vim.cmd.compiler('gcc')
vim.opt_local.errorformat:append('%-G%.%#')

local binary = vim.fn.shellescape(
    vim.fs.joinpath(
        vim.fn.fnamemodify(vim.fn.tempname(), ':h'),
        vim.fn.expand('%:t:r')
    )
)

local makeprg = {
    'c++',
}
local compile_flags = vim.fs.find('compile_flags.txt', {
    path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
    upward = true,
    type = 'file',
})[1]
if compile_flags then
    makeprg[#makeprg + 1] = vim.fn.shellescape('@' .. compile_flags)
end
vim.list_extend(makeprg, {
    '-Wall',
    '-Wextra',
    '-g',
    '-fdiagnostics-color=never',
    '-o',
    binary,
    '%:S',
})
vim.bo.makeprg = table.concat(makeprg, ' ')
local run = type(vim.b.run) == 'table' and vim.b.run or {}
run.command = binary
vim.b.run = run
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl mp< efm< | unl! b:current_compiler b:run.command b:man_default_sects'
