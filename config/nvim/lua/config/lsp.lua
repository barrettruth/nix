local M = {}

local CompletionItemKind = vim.lsp.protocol.CompletionItemKind
local Methods = vim.lsp.protocol.Methods

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

---@param text string
---@param max_width integer
---@return string
local function ellipsize(text, max_width)
    if text == '' or vim.fn.strdisplaywidth(text) <= max_width then
        return text
    end
    return vim.fn.strcharpart(text, 0, math.max(1, max_width - 1)) .. '…'
end

local function callable_completion(kind)
    return kind == CompletionItemKind.Constructor
        or kind == CompletionItemKind.Function
        or kind == CompletionItemKind.Method
end

local function completion_abbr(item)
    local label = item.label
    if callable_completion(item.kind) then
        label = label:match('^[^%(]+') or label
    end
    return vim.trim(label)
end

local function completion_menu(item)
    return vim.tbl_get(item, 'labelDetails', 'description') or item.detail or ''
end

local function completion_convert(item)
    local function completion_widths()
        local width = vim.api.nvim_win_get_width(0)
        if width < 100 then
            return 24, 0
        end
        if width < 140 then
            return 32, 0
        end
        return 40, 24
    end

    local abbr_width, menu_width = completion_widths()
    local menu = completion_menu(item)
    if menu_width > 0 then
        menu = ellipsize(menu, menu_width)
    else
        menu = ''
    end
    return {
        abbr = ellipsize(completion_abbr(item), abbr_width),
        menu = menu,
    }
end

---@param client vim.lsp.Client
---@param bufnr integer
function M.on_attach(client, bufnr)
    if client:supports_method(Methods.textDocument_completion) then
        vim.lsp.completion.enable(true, client.id, bufnr, {
            autotrigger = false,
            convert = completion_convert,
        })
    end

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
            'go',
            fzf_or('lsp_document_symbols', vim.lsp.buf.document_symbol),
            'document symbols',
        },
        {
            Methods.workspace_symbol,
            'gO',
            fzf_or('lsp_workspace_symbols', vim.lsp.buf.workspace_symbol),
            'workspace symbols',
        },
        {
            Methods.workspace_diagnostic,
            'gw',
            fzf_or('lsp_workspace_diagnostics', vim.diagnostic.setqflist),
            'workspace diagnostics',
        },
    }

    for _, m in ipairs(mappings) do
        local method, key, cmd, desc = unpack(m)
        if method and client:supports_method(method) then
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
