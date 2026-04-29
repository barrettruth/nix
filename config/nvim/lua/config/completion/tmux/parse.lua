local M = {}

function M.parse_descriptions(man_stdout, names_stdout)
    local lines = {}
    for line in (man_stdout .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end

    local commands = {}
    for name in names_stdout:gmatch('[^\n]+') do
        commands[name] = true
    end

    local defs = {}
    for i, line in ipairs(lines) do
        local command = line:match('^     ([a-z][a-z-]+)')
            or line:match('^       ([a-z][a-z-]+)')
        if command and commands[command] then
            local rest = line:sub((line:find(command, 1, true) or 1) + #command)
            if rest == '' or rest:match('^%s+%[') or rest:match('^%s%s+') then
                defs[#defs + 1] = { command = command, line = i }
            end
        end
    end

    local descriptions = {}
    for idx, def in ipairs(defs) do
        local block_end = (defs[idx + 1] and defs[idx + 1].line or #lines) - 1
        local j = def.line + 1

        while j <= block_end do
            local line = lines[j]
            if line:match('^%s+%(alias:') or vim.trim(line) == '' then
                j = j + 1
            elseif
                line:match('^             ') or line:match('^               ')
            then
                local stripped = vim.trim(line)
                if stripped == '' or stripped:match('[%[%]]') then
                    j = j + 1
                else
                    break
                end
            else
                break
            end
        end

        local desc_lines = {}
        for k = j, block_end do
            desc_lines[#desc_lines + 1] = lines[k]
        end

        local paragraphs = { {} }
        for _, line in ipairs(desc_lines) do
            local stripped = vim.trim(line)
            if stripped == '' then
                if #paragraphs[#paragraphs] > 0 then
                    paragraphs[#paragraphs + 1] = {}
                end
            else
                local para = paragraphs[#paragraphs]
                para[#para + 1] = stripped
            end
        end

        local parts = {}
        for _, para in ipairs(paragraphs) do
            if #para > 0 then
                parts[#parts + 1] = table.concat(para, ' ')
            end
        end

        local desc = table.concat(parts, '\n\n')
        desc = desc:gsub(string.char(0xe2, 0x80, 0x90) .. ' ', '')
        desc = desc:gsub('  +', ' ')
        if desc ~= '' then
            descriptions[def.command] = desc
        end
    end

    return descriptions
end

function M.parse(commands_stdout, descriptions)
    local items = {}

    for line in commands_stdout:gmatch('[^\n]+') do
        local name, alias = line:match('^([a-z-]+)%s+%(([a-z-]+)%)')
        if not name then
            name = line:match('^([a-z-]+)')
        end

        if name then
            local info = line
            if alias then
                info = info .. '\n\nalias: ' .. alias
            end
            if descriptions[name] then
                info = info .. '\n\n' .. descriptions[name]
            end

            items[#items + 1] = {
                abbr = name,
                info = info,
                kind = 'c',
                menu = '[tmux]',
                word = name,
            }
        end
    end

    table.sort(items, function(a, b)
        return a.word < b.word
    end)

    return items
end

return M
