---@class config.completion
local M = {}

local util = require('config.completion.util')

local provider_modules = {
    'config.completion.env',
}

---@type config.completion.Provider[]?
local provider_list

---@type table<string, config.completion.Provider>?
local providers_by_source

---@return config.completion.Provider[]
local function providers()
    if provider_list then
        return provider_list
    end

    provider_list = {}
    providers_by_source = {}

    for _, module_name in ipairs(provider_modules) do
        ---@type config.completion.Provider
        local provider = require(module_name)
        provider_list[#provider_list + 1] = provider
        if provider.source then
            providers_by_source[provider.source] = provider
        end
    end

    return provider_list
end

---@param item config.completion.Item
---@return config.completion.Provider?
local function provider_for(item)
    local source = vim.tbl_get(item, 'user_data', 'source')
    if type(source) ~= 'string' or source == '' then
        return
    end

    providers()

    return providers_by_source and providers_by_source[source] or nil
end

---@param item config.completion.Item|string
---@return config.completion.Item
local function normalize_item(item)
    if type(item) == 'string' then
        return { word = item }
    end

    return item
end

---@param item config.completion.Item
---@return string?
local function item_key(item)
    local word = item.word
    if word == '' then
        return
    end

    return item.icase and item.icase ~= 0 and word:lower() or word
end

function M.complete(findstart, base)
    local ctx = util.context(base)
    local active_providers = providers()

    if findstart == 1 then
        local fallback = -2
        local start

        for _, provider in ipairs(active_providers) do
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

    for _, provider in ipairs(active_providers) do
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

function M.on_complete_done()
    local item = vim.v.completed_item
    if type(item) ~= 'table' then
        return
    end

    local provider = provider_for(item)
    if not provider or not provider.on_complete_done then
        return
    end

    provider.on_complete_done(item, util.context(''))
end

vim.api.nvim_create_autocmd('CompleteDone', {
    group = vim.api.nvim_create_augroup('ACompletion', { clear = true }),
    callback = M.on_complete_done,
})

return M
