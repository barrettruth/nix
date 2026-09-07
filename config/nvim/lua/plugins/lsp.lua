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

            local group =
                vim.api.nvim_create_augroup('ALiveRename', { clear = true })

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
                group = group,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
                callback = function(o)
                    local id = o.data.client_id
                    local client = assert(vim.lsp.get_client_by_id(id))
                    local method = 'textDocument/rename'
                    if not client:supports_method(method) then
                        return
                    end
                    local clients =
                        vim.lsp.get_clients({ bufnr = o.buf, method = method })
                    if #clients == 1 then
                        vim.keymap.del('n', 'grn', { buffer = o.buf })
                    end
                end,
                group = group,
            })
        end,
        keys = { 'grn' },
    },
}
