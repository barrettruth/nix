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
    init_options = {
        fallbackFlags = { '-std=c++23' },
    },
    capabilities = {
        textDocument = {
            completion = {
                editsNearCursor = true,
            },
        },
    },
}
