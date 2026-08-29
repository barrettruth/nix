vim.pack.add({
    'https://github.com/neovim/nvim-lspconfig',
})

vim.pack.add({
    'https://github.com/folke/lazydev.nvim',
    'https://github.com/mrcjkb/rustaceanvim',
    'https://github.com/saecki/live-rename.nvim',
}, { load = function() end })

return {
    {
        'neovim/nvim-lspconfig',
    },
    {
        'folke/lazydev.nvim',
        ft = 'lua',
        after = function()
            require('lazydev').setup({
                library = {
                    { path = '${3rd}/luv/library' },
                },
            })
        end,
    },
    {
        'saecki/live-rename.nvim',
        event = 'LspAttach',
        after = function()
            local live_rename = require('live-rename')

            live_rename.setup()

            vim.api.nvim_create_autocmd('LspAttach', {
                callback = function(o)
                    local client = vim.lsp.get_client_by_id(o.data.client_id)
                    if
                        client and client:supports_method('textDocument/rename')
                    then
                        vim.keymap.set(
                            'n',
                            'grn',
                            live_rename.rename,
                            { buf = o.buf, desc = 'rename symbol' }
                        )
                    end
                end,
                group = vim.api.nvim_create_augroup(
                    'ALiveRename',
                    { clear = true }
                ),
            })
        end,
        keys = { 'grn' },
    },
    {
        'mrcjkb/rustaceanvim',
        ft = 'rust',
        before = function()
            vim.g.rustaceanvim = {
                server = {
                    standalone = false,
                    capabilities = {
                        general = { positionEncodings = { 'utf-16' } },
                    },
                    on_attach = function(_, bufnr)
                        vim.keymap.set(
                            'n',
                            '\\Rc',
                            '<cmd>RustLsp codeAction<cr>',
                            { buf = bufnr, desc = 'rust code action' }
                        )
                        vim.keymap.set(
                            'n',
                            '\\Rm',
                            '<cmd>RustLsp expandMacro<cr>',
                            { buf = bufnr, desc = 'rust expand macro' }
                        )
                        vim.keymap.set(
                            'n',
                            '\\Ro',
                            '<cmd>RustLsp openCargo<cr>',
                            { buf = bufnr, desc = 'rust open cargo' }
                        )
                    end,
                    default_settings = {
                        ['rust-analyzer'] = {
                            check = {
                                overrideCommand = {
                                    'cargo',
                                    'clippy',
                                    '--message-format=json',
                                    '--',
                                    '-W',
                                    'clippy::expect_used',
                                    '-W',
                                    'clippy::pedantic',
                                    '-W',
                                    'clippy::unwrap_used',
                                },
                            },
                        },
                    },
                },
            }
        end,
    },
}
