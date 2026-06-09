---Async-injection lifecycle for omnifunc-backed providers (`forge_refs`,
---`git_log`): `set` on a cache miss, `try_inject` once the fetch settles.
---Owns the generation counter and the staleness re-checks (gen/buf/mode/row)
---guarding the `vim.fn.complete()` call.
local M = {}

---@class config.completion.async.Pending
---@field gen integer
---@field bufnr integer
---@field row integer
---@field start_col integer
---@field [string] any

---@class config.completion.async.Lifecycle
---@field set fun(p: table)
---@field clear fun()
---@field generation fun(): integer
---@field try_inject fun(check: fun(pending: any): config.completion.Items?)

---@return config.completion.async.Lifecycle
function M.new_lifecycle()
    ---@type config.completion.async.Pending?
    local pending
    local generation = 0
    return {
        set = function(p)
            generation = generation + 1
            p.gen = generation
            pending = p
        end,
        clear = function()
            pending = nil
        end,
        generation = function()
            return generation
        end,
        try_inject = function(check)
            if not pending then
                return
            end
            local p = pending
            vim.schedule(function()
                if not pending or pending.gen ~= p.gen then
                    return
                end
                if vim.api.nvim_get_current_buf() ~= p.bufnr then
                    return
                end
                if not vim.fn.mode():find('i') then
                    return
                end
                local cursor = vim.api.nvim_win_get_cursor(0)
                if cursor[1] ~= p.row then
                    return
                end
                local items = check(p)
                if not items or #items == 0 then
                    return
                end
                pending = nil
                vim.fn.complete(p.start_col + 1, items)
            end)
        end,
    }
end

---@type table<string, fun(selected: integer, item: config.completion.Item)>
local doc_handlers = {}

---@param source string
---@param handler fun(selected: integer, item: config.completion.Item)
function M.register_doc_handler(source, handler)
    doc_handlers[source] = handler
end

vim.api.nvim_create_autocmd('CompleteChanged', {
    group = vim.api.nvim_create_augroup('AAsyncCompleteDocs', { clear = true }),
    callback = function()
        local item = vim.v.event.completed_item or {}
        local source = vim.tbl_get(item, 'user_data', 'source')
        if type(source) ~= 'string' then
            return
        end
        local handler = doc_handlers[source]
        if not handler then
            return
        end
        local selected = vim.fn.complete_info({ 'selected' }).selected
        if selected < 0 then
            return
        end
        handler(selected, item)
    end,
})

return M
