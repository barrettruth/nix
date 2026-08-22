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
            vim.diagnostic.open_float({ bufnr = bufnr, scope = 'cursor' })
        end,
    },
})

vim.lsp.config('*', {
    on_attach = lsp.on_attach,
})

---@param server string
local function compose_on_attach(server)
    local config = vim.lsp.config[server]
    if not config then
        return
    end
    local server_on_attach = config.on_attach
    if not server_on_attach or server_on_attach == lsp.on_attach then
        return
    end

    vim.lsp.config(server, {
        on_attach = function(client, bufnr)
            lsp.on_attach(client, bufnr)
            server_on_attach(client, bufnr)
        end,
    })
end

local enabled = {
    'bashls',
    'basedpyright',
    'clangd',
    'cssls',
    'emmet_language_server',
    'eslint',
    'html',
    'nixd',
    'mdx_analyzer',
    'jsonls',
    'pytest_lsp',
    'lua_ls',
    'ruff',
    'tailwindcss',
    'tinymist',
    'ts_query_ls',
    'vimdoc_ls',
    'vtsls',
}

for _, server in ipairs(enabled) do
    compose_on_attach(server)
end
vim.lsp.enable(enabled)

-- remove duplicate entries from goto defintion list
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
