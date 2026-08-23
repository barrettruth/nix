return {
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
    on_attach = function(_, bufnr)
        vim.keymap.set('n', 'gD', function()
            vim.cmd.VtsExec('goto_source_definition')
        end, { buf = bufnr, desc = 'goto source definition' })
    end,
}
