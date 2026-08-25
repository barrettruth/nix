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

-- vim.lsp.config folds every lsp/<server>.lua on the runtimepath with
-- tbl_deep_extend('force'), so an after/lsp override replaces a plugin's
-- on_attach instead of running after it; collect each one and call them all
---@param server string
local function compose_on_attach(server)
    local on_attaches = { lsp.on_attach }
    for _, file in
        ipairs(
            vim.api.nvim_get_runtime_file(('lsp/%s.lua'):format(server), true)
        )
    do
        local on_attach = assert(loadfile(file))().on_attach
        if on_attach then
            on_attaches[#on_attaches + 1] = on_attach
        end
    end
    if #on_attaches == 1 then
        return
    end

    vim.lsp.config(server, {
        on_attach = function(client, bufnr)
            for _, on_attach in ipairs(on_attaches) do
                on_attach(client, bufnr)
            end
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
    'lua_ls',
    'ocamllsp',
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
