local M = {}
M.source = 'env'

local function state(ctx)
    local base = ctx.before:match('%$([%w_]*)$')
    if base ~= nil then
        return {
            base = base,
            marker = '$',
            start = ctx.col - #base,
        }
    end

    base = ctx.before:match('%${([%w_]*)$')
    if base ~= nil then
        return {
            base = base,
            marker = '${',
            start = ctx.col - #base,
        }
    end
end

local function info(name, value)
    local text = tostring(value):gsub('%s+', ' ')
    if #text > 120 then
        text = text:sub(1, 117) .. '...'
    end
    return ('$%s=%s'):format(name, text)
end

function M.findstart(ctx)
    local st = state(ctx)
    return st and st.start or nil
end

function M.complete(ctx)
    local st = state(ctx)
    if not st then
        return {}
    end

    local env = vim.fn.environ()
    local query = st.base:lower()
    local names = {}

    for name in pairs(env) do
        if query == '' or name:lower():sub(1, #query) == query then
            names[#names + 1] = name
        end
    end

    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)

    local words = {}
    for _, name in ipairs(names) do
        words[#words + 1] = {
            word = name,
            abbr = st.marker .. name,
            icase = 1,
            info = info(name, env[name]),
            kind = 'e',
            menu = '[env]',
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

function M.on_complete_done(item)
    if not vim.tbl_get(item, 'user_data', 'env', 'close_brace') then
        return
    end

    local word = item.word
    if type(word) ~= 'string' or word == '' then
        return
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
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
