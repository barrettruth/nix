local M = {}

---@param fzf_cmd string `:FzfLua` subcommand
---@param fallback fun()
---@return fun()
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

---@param client vim.lsp.Client
---@param bufnr integer
function M.on_attach(client, bufnr)
    if client:supports_method('textDocument/hover') then
        vim.keymap.set(
            'n',
            'K',
            vim.lsp.buf.hover,
            { buf = bufnr, desc = 'hover' }
        )
    end

    local mappings = {
        {
            'textDocument/codeAction',
            'gra',
            fzf_or('lsp_code_actions', vim.lsp.buf.code_action),
            'code action',
        },
        {
            'textDocument/declaration',
            'gD',
            fzf_or('lsp_declarations', vim.lsp.buf.declaration),
            'declaration',
        },
        {
            'textDocument/definition',
            'gd',
            fzf_or('lsp_definitions', vim.lsp.buf.definition),
            'definition',
        },
        {
            'textDocument/implementation',
            'gri',
            fzf_or('lsp_implementations', vim.lsp.buf.implementation),
            'implementation',
        },
        {
            'textDocument/references',
            'grr',
            fzf_or('lsp_references', vim.lsp.buf.references),
            'references',
        },
        {
            'textDocument/typeDefinition',
            'grt',
            fzf_or('lsp_typedefs', vim.lsp.buf.type_definition),
            'type definition',
        },
        {
            'textDocument/documentSymbol',
            'go',
            fzf_or('lsp_document_symbols', vim.lsp.buf.document_symbol),
            'document symbols',
        },
        {
            'workspace/symbol',
            'gO',
            fzf_or('lsp_workspace_symbols', vim.lsp.buf.workspace_symbol),
            'workspace symbols',
        },
        {
            'workspace/diagnostic',
            'gw',
            fzf_or('lsp_workspace_diagnostics', vim.diagnostic.setqflist),
            'workspace diagnostics',
        },
    }

    for _, m in ipairs(mappings) do
        local method, key, cmd, desc = unpack(m)
        if client:supports_method(method) then
            vim.keymap.set('n', key, cmd, { buf = bufnr, desc = desc })
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
