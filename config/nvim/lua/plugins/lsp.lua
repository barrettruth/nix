vim.pack.add({
    'https://github.com/neovim/nvim-lspconfig',
})

vim.pack.add({
    'https://github.com/folke/lazydev.nvim',
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
                    local clients = vim.lsp.get_clients({ buffer = o.buf })
                    for _, client in ipairs(clients) do
                        if client:supports_method('textDocument/rename') then
                            vim.keymap.set(
                                'n',
                                'grn',
                                live_rename.rename,
                                { buffer = o.buf, desc = 'rename symbol' }
                            )
                        end
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
        'yioneko/nvim-vtsls',
        enabled = false,
        after = function()
            require('vtsls').config({
                on_attach = function(_, bufnr)
                    vim.keymap.set(
                        'n',
                        'gD',
                        vim.cmd.VtsExec('goto_source_definition'),
                        { buffer = bufnr, desc = 'goto source definition' }
                    )
                end,
                settings = {
                    typescript = {
                        inlayHints = {
                            parameterNames = { enabled = 'literals' },
                            parameterTypes = { enabled = true },
                            variableTypes = { enabled = true },
                            propertyDeclarationTypes = { enabled = true },
                            functionLikeReturnTypes = { enabled = true },
                            enumMemberValues = { enabled = true },
                        },
                    },
                },
                handlers = {
                    ['textDocument/publishDiagnostics'] = function(
                        _,
                        result,
                        ctx
                    )
                        if not result.diagnostics then
                            return
                        end

                        local idx = 1
                        while idx <= #result.diagnostics do
                            local entry = result.diagnostics[idx]

                            if
                                vim.tbl_contains({ 80001, 80006 }, entry.code)
                            then
                                table.remove(result.diagnostics, idx)
                            else
                                idx = idx + 1
                            end
                        end

                        vim.lsp.diagnostic.on_publish_diagnostics(
                            _,
                            result,
                            ctx
                        )
                    end,
                },
            })
        end,
    },
    {
        'mrcjkb/rustaceanvim',
        enabled = false,
        ft = 'rust',
        before = function()
            vim.g.rustaceanvim = {
                server = {
                    standalone = false,
                    capabilities = {
                        general = { positionEncodings = { 'utf-16' } },
                    },
                    on_attach = function(client, bufnr)
                        require('config.lsp').on_attach(client, bufnr)
                        vim.keymap.set(
                            'n',
                            '\\Rc',
                            '<cmd>RustLsp codeAction<cr>',
                            { buffer = bufnr, desc = 'rust code action' }
                        )
                        vim.keymap.set(
                            'n',
                            '\\Rm',
                            '<cmd>RustLsp expandMacro<cr>',
                            { buffer = bufnr, desc = 'rust expand macro' }
                        )
                        vim.keymap.set(
                            'n',
                            '\\Ro',
                            '<cmd>RustLsp openCargo<cr>',
                            { buffer = bufnr, desc = 'rust open cargo' }
                        )
                    end,
                    default_settings = {
                        ['rust-analyzer'] = {
                            checkOnSave = {
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
