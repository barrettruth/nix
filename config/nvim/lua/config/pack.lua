vim.g.loaded_2html_plugin = true
vim.g.loaded_bugreport = true
vim.g.loaded_getscript = true
vim.g.loaded_getscriptPlugin = true
vim.g.loaded_gzip = true
vim.g.loaded_logipat = true
vim.g.loaded_netrw = true
vim.g.loaded_netrwFileHandlers = true
vim.g.loaded_netrwPlugin = true
vim.g.loaded_netrwSettings = true
vim.g.loaded_optwin = true
vim.g.loaded_rplugin = true
vim.g.loaded_rrhelper = true
vim.g.loaded_synmenu = true
vim.g.loaded_tar = true
vim.g.loaded_tarPlugin = true
vim.g.loaded_tohtml = true
vim.g.loaded_tutor = true
vim.g.loaded_vimball = true
vim.g.loaded_vimballPlugin = true
vim.g.loaded_zip = true
vim.g.loaded_zipPlugin = true

local dev_plugins = {
    ['diffs.nvim'] = '~/dev/diffs.nvim',
    ['canola.nvim'] = '~/dev/canola.nvim',
    ['pending.nvim'] = '~/dev/pending.nvim',
}

for _, path in pairs(dev_plugins) do
    vim.opt.rtp:prepend(path)
end

vim.g.lz_n = {
    load = function(name)
        name = name:match('[^/]+$') or name
        if not dev_plugins[name] then
            vim.cmd.packadd(name)
        end
    end,
}

vim.pack.add({
    'https://github.com/lumen-oss/lz.n',
})

require('lz.n').load('plugins')
