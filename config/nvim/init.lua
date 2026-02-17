vim.g.mapleader = ' '

function _G.map(mapping, opts)
    vim.keymap.set(
        mapping[1],
        mapping[2],
        mapping[3],
        vim.tbl_extend('keep', opts or {}, { silent = true })
    )
end

function _G.bmap(mapping, opts)
    _G.map(mapping, vim.tbl_extend('force', opts or {}, { buffer = 0 }))
end

local disabled_plugins = {
    '2html_plugin',
    'bugreport',
    'getscript',
    'getscriptPlugin',
    'gzip',
    'logipat',
    'netrw',
    'netrwFileHandlers',
    'netrwPlugin',
    'netrwSettings',
    'optwin',
    'rplugin',
    'rrhelper',
    'synmenu',
    'tar',
    'tarPlugin',
    'tohtml',
    'tutor',
    'vimball',
    'vimballPlugin',
    'zip',
    'zipPlugin',
}

for _, plugin in ipairs(disabled_plugins) do
    vim.g['loaded_' .. plugin] = 1
end

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
    local out = vim.fn.system({
        'git',
        'clone',
        '--filter=blob:none',
        '--branch=stable',
        lazyrepo,
        lazypath,
    })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
            { out, 'WarningMsg' },
            { '\nPress any key to exit...' },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup('plugins', {
    change_detection = { enabled = false },
})
