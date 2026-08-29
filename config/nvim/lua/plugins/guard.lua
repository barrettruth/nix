vim.pack.add({
    'https://github.com/nvimdev/guard.nvim',
    'https://github.com/nvimdev/guard-collection',
}, { load = function() end })

return {
    'nvimdev/guard.nvim',
    lazy = false,
    before = function()
        require('config.lz').load('guard-collection')
        vim.g.guard_config = {
            fmt_on_save = false,
            save_on_fmt = true,
            lsp_as_default_formatter = true,
        }
    end,
    keys = {
        { 'gF', '<cmd>Guard fmt<cr>', mode = { 'n', 'x' } },
    },
    after = function()
        local ft = require('guard.filetype')

        ft(
            'javascript,javascriptreact,typescript,typescriptreact,css,graphql,html,json,jsonc,mdx,markdown,yaml'
        ):fmt({
            cmd = 'prettier',
            args = { '--stdin-filepath' },
            fname = true,
            stdin = true,
        })
        ft('sh,bash'):fmt({
            cmd = 'shfmt',
            args = { '-i', '2' },
            stdin = true,
        }):lint('shellcheck')
        ft('zsh'):lint('zsh')
    end,
}
