local M = {}

local util = require('config.completion.util')

---@param stdout string
---@return config.completion.Items
function M.parse_keys(stdout)
    local items = {}
    local doc_lines = {}
    local seen = {}

    for _, line in ipairs(util.lines(stdout)) do
        if line:match('^#') then
            doc_lines[#doc_lines + 1] = line:gsub('^# ?', '')
        else
            local key = line:match('^([a-z][a-z0-9-]*)%s*=')
            if key and not seen[key] then
                seen[key] = true
                items[#items + 1] = {
                    abbr = key,
                    icase = 1,
                    info = #doc_lines > 0 and table.concat(doc_lines, '\n')
                        or nil,
                    kind = 'k',
                    menu = '[ghostty]',
                    user_data = {
                        source = 'ghostty',
                    },
                    word = key,
                }
            end
            doc_lines = {}
        end
    end

    table.sort(items, function(a, b)
        return a.word < b.word
    end)

    return items
end

---@param content string
---@return table<string, string[]>
function M.parse_enums(content)
    local enums = {}

    for _, line in ipairs(util.lines(content)) do
        local key = line:match('%-%-([a-z][a-z0-9-]*)%)')
        local values = line:match('compgen %-W "([^"]+)"')
        if key and values then
            local items = {}
            local seen = {}

            for value in values:gmatch('%S+') do
                if not seen[value] then
                    seen[value] = true
                    items[#items + 1] = value
                end
            end

            if #items > 0 then
                table.sort(items, function(a, b)
                    return a < b
                end)
                enums[key] = items
            end
        end
    end

    return enums
end

return M
