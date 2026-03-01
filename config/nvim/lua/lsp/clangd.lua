vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.name == 'clangd' then
            vim.keymap.set(
                'n',
                'gh',
                vim.cmd.ClangdSwitchSourceHeader,
                { buffer = args.buf }
            )
        end
    end,
    group = vim.api.nvim_create_augroup('AClangdKeymap', { clear = true }),
})

return {
    filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
    cmd = {
        'clangd',
        '--clang-tidy',
        '-j=4',
        '--background-index',
        '--completion-style=bundled',
        '--header-insertion=iwyu',
        '--header-insertion-decorators=false',
    },
    capabilities = {
        textDocument = {
            completion = {
                editsNearCursor = true,
            },
        },
    },
}
