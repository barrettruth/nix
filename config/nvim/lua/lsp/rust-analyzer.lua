return {
    standalone = false,
    capabilities = { general = { positionEncodings = { 'utf-16' } } },
    settings = {
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
    on_attach = function(...)
        require('config.lsp').on_attach(...)
        vim.keymap.set(
            'n',
            '\\Rc',
            '<cmd>RustLsp codeAction<cr>',
            { buffer = 0 }
        )
        vim.keymap.set(
            'n',
            '\\Rm',
            '<cmd>RustLsp expandMacro<cr>',
            { buffer = 0 }
        )
        vim.keymap.set(
            'n',
            '\\Ro',
            '<cmd>RustLsp openCargo<cr>',
            { buffer = 0 }
        )
    end,
}
