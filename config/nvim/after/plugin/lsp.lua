local lsp = require('config.lsp')

vim.diagnostic.config({
    signs = false,
    float = {
        format = function(diagnostic)
            return ('%s (%s)'):format(diagnostic.message, diagnostic.source)
        end,
        header = '',
        prefix = ' ',
    },
    jump = {
        on_jump = function(_, bufnr)
            vim.diagnostic.open_float({
                bufnr = bufnr,
                scope = 'cursor',
                focus = false,
            })
        end,
    },
})

vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(o)
        local client = vim.lsp.get_client_by_id(o.data.client_id)
        if client then
            lsp.on_attach(client, o.buf)
        end
    end,
    group = vim.api.nvim_create_augroup('ALsp', { clear = true }),
})

local servers = {
    'bashls',
    'basedpyright',
    'bazel_ls',
    'clangd',
    'cssls',
    'eslint',
    'html',
    'nixd',
    'mdx_analyzer',
    'jsonls',
    'kotlin_language_server',
    'lua_ls',
    'ocamllsp',
    'ruff',
    'tinymist',
    'ts_query_ls',
    'vimdoc_ls',
    'vtsls',
}

local available_servers = vim.iter(servers)
    :filter(function(name)
        local cmd = vim.lsp.config[name].cmd
        if type(cmd) == 'function' then
            return true
        end

        return type(cmd) == 'table'
            and type(cmd[1]) == 'string'
            and vim.fn.executable(cmd[1]) == 1
    end)
    :totable()

vim.lsp.enable(available_servers)

-- remove duplicate entries from goto definition list
-- example: https://github.com/LuaLS/lua-language-server/issues/2451
local locations_to_items = vim.lsp.util.locations_to_items
vim.lsp.util.locations_to_items = function(locations, offset_encoding)
    local seen = {}
    local deduped = {}
    for _, loc in ipairs(locations) do
        local uri = loc.uri or loc.targetUri
        local range = loc.range or loc.targetSelectionRange
        local key = uri .. range.start.line
        if not seen[key] then
            seen[key] = true
            deduped[#deduped + 1] = loc
        end
    end

    return locations_to_items(deduped, offset_encoding)
end
