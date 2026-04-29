local M = {}

local provider_modules = {
    'config.completion.lazydev',
    'config.completion.env',
    'config.completion.conventional_commits',
}

local function providers()
    local loaded = {}
    for _, module in ipairs(provider_modules) do
        local ok, provider = pcall(require, module)
        if ok then
            loaded[#loaded + 1] = provider
        end
    end
    return loaded
end

local function provider_for(item)
    local source = vim.tbl_get(item, 'user_data', 'source')
    if type(source) ~= 'string' or source == '' then
        return
    end

    for _, provider in ipairs(providers()) do
        if provider.source == source then
            return provider
        end
    end
end

local function normalize_item(item)
    return type(item) == 'string' and { word = item } or item
end

local function item_key(item)
    local word = item.word
    if not word or word == '' then
        return
    end
    return item.icase and item.icase ~= 0 and word:lower() or word
end

local function context(base)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    return {
        base = base,
        before = line:sub(1, col),
        bufnr = vim.api.nvim_get_current_buf(),
        col = col,
        filetype = vim.bo.filetype,
        line = line,
        row = row,
    }
end

function M.complete(findstart, base)
    local ctx = context(base)

    if findstart == 1 then
        local fallback = -2
        local start

        for _, provider in ipairs(providers()) do
            local value = provider.findstart and provider.findstart(ctx)
            if type(value) == 'number' then
                if value >= 0 then
                    start = start and math.min(start, value) or value
                elseif fallback ~= -3 then
                    fallback = value
                end
            end
        end

        return start or fallback
    end

    local words = {}
    local seen = {}

    for _, provider in ipairs(providers()) do
        local items = provider.complete and provider.complete(ctx) or {}
        for _, raw in ipairs(items) do
            local item = normalize_item(raw)
            local key = item_key(item)
            if item.dup == 1 or not key or not seen[key] then
                if key and item.dup ~= 1 then
                    seen[key] = true
                end
                words[#words + 1] = item
            end
        end
    end

    return {
        refresh = 'always',
        words = words,
    }
end

function M.convert_lsp_item(item)
    local converted = {}
    local ctx = context('')

    for _, provider in ipairs(providers()) do
        local value = provider.convert_lsp_item
            and provider.convert_lsp_item(item, ctx)
        if type(value) == 'table' then
            converted = vim.tbl_extend('force', converted, value)
        end
    end

    return converted
end

function M.on_complete_done()
    local item = vim.v.completed_item
    if type(item) ~= 'table' then
        return
    end

    local provider = provider_for(item)
    if not provider or not provider.on_complete_done then
        return
    end

    provider.on_complete_done(item, context(''))
end

vim.api.nvim_create_autocmd('CompleteDone', {
    group = vim.api.nvim_create_augroup('ACompletion', { clear = true }),
    callback = M.on_complete_done,
})

return M
