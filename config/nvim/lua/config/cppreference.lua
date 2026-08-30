local M = {}

local search_url =
    'https://en.cppreference.com/index.php?title=Special%3ASearch&search='

local inline_namespaces = {
    '__1',
    '__cxx11',
    '__ndk1',
    '_V2',
}

local function notify(message, level)
    vim.notify('cppreference: ' .. message, level or vim.log.levels.INFO)
end

local function normalize(query)
    query = vim.trim(query or ''):gsub('%s*::%s*', '::'):gsub('^::', '')
    for _, namespace in ipairs(inline_namespaces) do
        query = query:gsub('::' .. namespace .. '::', '::')
    end
    return vim.trim(query:gsub('%s+', ' '))
end

local function search(query)
    query = normalize(query)
    if query == '' then
        notify('no symbol under cursor')
        return
    end

    local _, err = vim.ui.open(search_url .. vim.uri_encode(query))
    if err then
        notify(tostring(err), vim.log.levels.ERROR)
    end
end

local function cursor_query()
    local line = vim.api.nvim_get_current_line()
    local header = line:match('^%s*#%s*include%s*([<"][^>"]+[>"])')
    if header then
        return header, true
    end
    return vim.fn.expand('<cword>'), false
end

local function symbol_details(result)
    if type(result) ~= 'table' then
        return
    end
    if result.name then
        return result
    end
    if type(result[1]) == 'table' then
        return result[1]
    end
end

local function semantic_query(symbol)
    local name = symbol.name or ''
    local container = (symbol.containerName or ''):gsub('::+$', '')
    if container == '' then
        return name
    end
    return container .. '::' .. name
end

local function clangd_client(bufnr)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.name == 'clangd' then
            return client
        end
    end
end

local function search_under_cursor()
    local bufnr = vim.api.nvim_get_current_buf()
    local fallback, direct = cursor_query()
    if direct then
        search(fallback)
        return
    end
    local client = clangd_client(bufnr)
    if not client then
        search(fallback)
        return
    end

    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local ok, request = pcall(
        client.request,
        client,
        'textDocument/symbolInfo',
        params,
        function(err, result)
            local symbol = not err and symbol_details(result)
            local query = symbol and semantic_query(symbol)
            search(query and query:match('^std::') and query or fallback)
        end,
        bufnr
    )
    if not ok or request == false then
        search(fallback)
    end
end

local function visual_selection()
    local lines = vim.fn.getregion(
        vim.fn.getpos('v'),
        vim.fn.getpos('.'),
        { type = vim.fn.mode() }
    )
    return table.concat(lines, ' ')
end

function M.setup()
    vim.api.nvim_buf_create_user_command(0, 'CPP', function(opts)
        if opts.args == '' then
            search_under_cursor()
        else
            search(opts.args)
        end
    end, { force = true, nargs = '*' })
    vim.keymap.set('n', 'gX', search_under_cursor, {
        buffer = true,
        desc = 'search cppreference',
    })
    vim.keymap.set('x', 'gX', function()
        search(visual_selection())
    end, { buffer = true, desc = 'search cppreference' })
end

return M
