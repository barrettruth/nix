local M = {}

local Methods = vim.lsp.protocol.Methods

local function fzf_or(fzf_cmd, fallback)
    return function()
        require('config.lz').load('ibhagwan/fzf-lua')
        if pcall(require, 'fzf-lua') then
            vim.cmd('FzfLua ' .. fzf_cmd)
        else
            fallback()
        end
    end
end

function M.on_attach(client, bufnr)
    if client:supports_method(Methods.textDocument_hover) then
        vim.keymap.set(
            'n',
            'K',
            vim.lsp.buf.hover,
            { buffer = bufnr, desc = 'hover' }
        )
    end

    local mappings = {
        {
            Methods.textDocument_codeAction,
            'gra',
            fzf_or('lsp_code_actions', vim.lsp.buf.code_action),
            'code action',
        },
        {
            Methods.textDocument_declaration,
            'gD',
            fzf_or('lsp_declarations', vim.lsp.buf.declaration),
            'declaration',
        },
        {
            Methods.textDocument_definition,
            'gd',
            fzf_or('lsp_definitions', vim.lsp.buf.definition),
            'definition',
        },
        {
            Methods.textDocument_implementation,
            'gri',
            fzf_or('lsp_implementations', vim.lsp.buf.implementation),
            'implementation',
        },
        {
            Methods.textDocument_references,
            'grr',
            fzf_or('lsp_references', vim.lsp.buf.references),
            'references',
        },
        {
            Methods.textDocument_typeDefinition,
            'grt',
            fzf_or('lsp_typedefs', vim.lsp.buf.type_definition),
            'type definition',
        },
        {
            Methods.textDocument_documentSymbol,
            'gs',
            fzf_or('lsp_document_symbols', vim.lsp.buf.document_symbol),
            'document symbols',
        },
        {
            Methods.workspace_diagnostic,
            '<leader>gW',
            fzf_or('lsp_workspace_diagnostics', vim.diagnostic.setqflist),
            'workspace diagnostics',
        },
        {
            Methods.workspace_symbol,
            '<leader>gS',
            fzf_or('lsp_workspace_symbols', vim.lsp.buf.workspace_symbol),
            'workspace symbols',
        },
    }

    for _, m in ipairs(mappings) do
        local method, key, cmd, desc = unpack(m)
        if client:supports_method(method) then
            vim.keymap.set('n', key, cmd, { buffer = bufnr, desc = desc })
        end
    end
end

function M.format()
    if pcall(require, 'guard.filetype') then
        vim.cmd.Guard('fmt')
    else
        vim.lsp.buf.format({ async = true })
    end
end

return M
