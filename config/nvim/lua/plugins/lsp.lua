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
}
