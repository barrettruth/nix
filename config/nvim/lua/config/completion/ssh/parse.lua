local M = {}

local query_to_keywords = {
    cipher = { 'Ciphers' },
    ['cipher-auth'] = { 'Ciphers' },
    mac = { 'MACs' },
    kex = { 'KexAlgorithms' },
    key = { 'HostKeyAlgorithms', 'PubkeyAcceptedAlgorithms' },
    ['key-sig'] = { 'CASignatureAlgorithms' },
}

local function keyword(line)
    return line:match('^     (%u[%a%d]+)%s*$')
        or line:match('^     (%u[%a%d]+)   ')
        or line:match('^     (%u[%a%d]+)  %u')
        or line:match('^       (%u[%a%d]+)%s*$')
        or line:match('^       (%u[%a%d]+)   ')
        or line:match('^       (%u[%a%d]+)  %u')
end

local function inline(line)
    return line:match('^     %u[%a%d]+%s%s+(.+)')
        or line:match('^       %u[%a%d]+%s%s+(.+)')
end

local function parse_value_list(fragment)
    fragment = fragment:gsub('%b()', '')
    fragment = fragment:gsub('"', '')
    fragment = fragment:gsub(' or ', ', ')
    fragment = fragment:gsub(' and ', ', ')
    local vals = {}
    local seen = {}
    for piece in (fragment .. ','):gmatch('%s*(.-),%s*') do
        piece = vim.trim(piece)
        if piece ~= '' and not piece:find('%s') then
            local val = piece:match('^([%a][%a%d-]+)$')
            if val and not seen[val] then
                seen[val] = true
                vals[#vals + 1] = val
            end
        end
    end
    return #vals >= 2 and vals or nil
end

function M.extract_enums_from_man(man_stdout)
    local lines = {}
    for line in (man_stdout .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end

    local defs = {}
    for i, line in ipairs(lines) do
        local kw = keyword(line)
        if kw then
            defs[#defs + 1] = { line = i, keyword = kw }
        end
    end

    local enums = {}
    for idx, def in ipairs(defs) do
        local block_end = (defs[idx + 1] and defs[idx + 1].line or #lines) - 1
        local parts = {}
        for k = def.line + 1, block_end do
            parts[#parts + 1] = lines[k]
        end
        local text = table.concat(parts, ' ')
        text = text:gsub(string.char(0xe2, 0x80, 0x90) .. '%s+', '')
        text = text:gsub('%s+', ' ')

        local list = text:match('[Tt]he argument must be (.-)%.')
            or text:match('[Tt]he argument to this keyword must be (.-)%.')
            or text:match('[Tt]he argument may be one of:? (.-)%.')
            or text:match('[Tt]he argument may be (.-)%.')
            or text:match('[Tt]he possible values are:? (.-)%.')
            or text:match('[Vv]alid arguments are (.-)%.')
            or text:match('[Vv]alid options are:? (.-)%.')
            or text:match('[Aa]ccepted values are (.-)%.')
        local vals = list and parse_value_list(list)

        if not vals then
            local fvals = {}
            local fseen = {}
            local function add(v)
                if v and #v >= 2 and not fseen[v] then
                    fseen[v] = true
                    fvals[#fvals + 1] = v
                end
            end
            for v1, v2 in
                text:gmatch(
                    ' is set to "?([%a][%a%d-]+)"? or "?([%a][%a%d-]+)"?'
                )
            do
                add(v1)
                add(v2)
            end
            for v in text:gmatch(' is set to "?([%a][%a%d-]+)"?') do
                add(v)
            end
            for v in text:gmatch('%u[%a%d]+ set to "?([%a][%a%d-]+)"?') do
                add(v)
            end
            for v in text:gmatch('When set to "?([%a][%a%d-]+)"?') do
                add(v)
            end
            for v in text:gmatch('[Ss]etting %S+ to "?([%a][%a%d-]+)"?') do
                add(v)
            end
            for v in text:gmatch('value %S+ be set to "?([%a][%a%d-]+)"?') do
                add(v)
            end
            local these = text:match('[Tt]hese options are:? (.-)%.')
            if these then
                local parsed = parse_value_list(these)
                if parsed then
                    for _, v in ipairs(parsed) do
                        add(v)
                    end
                end
            end
            for v in text:gmatch('[Tt]he default is "?([%a][%a%d-]+)"?') do
                if v ~= 'to' then
                    add(v)
                end
            end
            for v in text:gmatch('[Tt]he default, "?([%a][%a%d-]+)"?') do
                add(v)
            end
            for v in text:gmatch('[Aa]n argument of "?([%a][%a%d-]+)"?') do
                add(v)
            end
            for v in text:gmatch('[Aa] value of "?([%a][%a%d-]+)"?') do
                add(v)
            end
            if #fvals >= 2 then
                vals = fvals
            end
        end

        if vals then
            enums[def.keyword:lower()] = vals
        end
    end

    return enums
end

function M.parse_keywords(stdout)
    local lines = {}
    for line in (stdout .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end

    local defs = {}
    for i, line in ipairs(lines) do
        local kw = keyword(line)
        if kw then
            defs[#defs + 1] = { line = i, keyword = kw, inline = inline(line) }
        end
    end

    local items = {}
    for idx, def in ipairs(defs) do
        local block_end = (defs[idx + 1] and defs[idx + 1].line or #lines) - 1
        local desc_lines = {}

        if def.inline then
            desc_lines[#desc_lines + 1] = '               ' .. def.inline
        end
        for k = def.line + 1, block_end do
            desc_lines[#desc_lines + 1] = lines[k]
        end

        local paragraphs = { {} }
        for _, dl in ipairs(desc_lines) do
            local stripped = vim.trim(dl)
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

        items[#items + 1] = {
            abbr = def.keyword,
            icase = 1,
            info = desc ~= '' and desc or nil,
            kind = 'k',
            menu = '[ssh]',
            word = def.keyword,
        }
    end

    table.sort(items, function(a, b)
        return a.word:lower() < b.word:lower()
    end)

    return items
end

function M.parse_enums(stdout, man_enums)
    local enums = {}
    for k, v in pairs(man_enums) do
        enums[k] = v
    end

    local current_query = nil
    for line in (stdout .. '\n'):gmatch('(.-)\n') do
        local query = line:match('^##(.+)')
        if query then
            current_query = query
        elseif current_query and line ~= '' then
            local keywords = query_to_keywords[current_query]
            if keywords then
                for _, kw in ipairs(keywords) do
                    local key = kw:lower()
                    enums[key] = enums[key] or {}

                    local seen = {}
                    for _, existing in ipairs(enums[key]) do
                        seen[existing] = true
                    end

                    if not seen[line] then
                        enums[key][#enums[key] + 1] = line
                    end
                end
            end
        end
    end

    for _, values in pairs(enums) do
        table.sort(values, function(a, b)
            return a:lower() < b:lower()
        end)
    end

    return enums
end

return M
