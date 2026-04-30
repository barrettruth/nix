---@type config.completion.Provider
local M = {
    source = 'env',
}

---@class config.completion.env.State
---@field base string
---@field marker '$'|'${'
---@field start integer

---@param ctx config.completion.Context
---@return config.completion.env.State?
local function state(ctx)
    local query = type(ctx.base) == 'string' and ctx.base or ''
    local base = ctx.before:match('%$([%w_]*)$')
    if base ~= nil then
        return {
            base = query ~= '' and query or base,
            marker = '$',
            start = ctx.col - #base,
        }
    end

    base = ctx.before:match('%${([%w_]*)$')
    if base ~= nil then
        return {
            base = query ~= '' and query or base,
            marker = '${',
            start = ctx.col - #base,
        }
    end
end

---@param value string
---@return string
local function info(value)
    local text = tostring(value):gsub('%s+', ' ')
    if #text > 120 then
        text = text:sub(1, 117) .. '...'
    end
    return text
end

---@param marker '$'|'${'
---@param name string
---@return string
local function abbr(marker, name)
    if marker == '${' then
        return marker .. name .. '}'
    end

    return marker .. name
end

---@param ctx config.completion.Context
---@return integer?
function M.findstart(ctx)
    local st = state(ctx)
    return st and st.start or nil
end

---@param ctx config.completion.Context
---@return config.completion.Items
function M.complete(ctx)
    local st = state(ctx)
    if not st then
        return {}
    end

    local env = vim.fn.environ()
    local query = st.base
    local names = {}

    for name in pairs(env) do
        names[#names + 1] = name
    end

    if query == '' then
        table.sort(names, function(a, b)
            return a:lower() < b:lower()
        end)
    else
        names = vim.fn.matchfuzzy(names, st.base, { matchseq = 1 })
    end

    local words = {}
    for _, name in ipairs(names) do
        words[#words + 1] = {
            word = name,
            abbr = abbr(st.marker, name),
            icase = 1,
            info = info(env[name]),
            kind = 'env',
            user_data = {
                env = {
                    close_brace = st.marker == '${',
                },
                source = M.source,
            },
        }
    end

    return words
end

---@param item config.completion.Item
function M.on_complete_done(item)
    if not vim.tbl_get(item, 'user_data', 'env', 'close_brace') then
        return
    end

    local word = item.word
    if type(word) ~= 'string' or word == '' then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local col = cursor[2]
    local line = vim.api.nvim_get_current_line()
    local insert_col

    for _, candidate in ipairs({ col, col + 1 }) do
        if candidate >= #word then
            local start = candidate - #word + 1
            if line:sub(start, candidate) == word then
                insert_col = candidate
                break
            end
        end
    end

    if not insert_col then
        return
    end

    if line:sub(insert_col + 1, insert_col + 1) == '}' then
        return
    end

    vim.api.nvim_buf_set_text(
        0,
        row - 1,
        insert_col,
        row - 1,
        insert_col,
        { '}' }
    )
end

return M
