--- Editor-side drivers for the nvim-{commit,edit,review} skills.
--- muxlib.call loads this by path per call, so a server answers with the code
--- on disk rather than whatever its module cache holds.

local view = require('mux.view')

local COMMIT_READY_MS = 6000

local M = {}

---@param payload { message?: string[] }
---@return table
function M.commit(payload)
    local message = payload.message or {}

    if #message == 0 then
        return { ok = false, error = 'empty commit message' }
    end

    local _, err = view.call('vcs', function()
        local existing = vim.fn.bufnr('COMMIT_EDITMSG')

        if existing > 0 then
            pcall(vim.cmd, 'silent! bwipeout! ' .. existing)
        end

        pcall(vim.cmd, 'silent! Git')
        pcall(vim.cmd, 'silent! only')
        pcall(vim.cmd, 'Git commit')

        return true
    end)

    if err then
        return { ok = false, error = err }
    end

    local ready = vim.wait(COMMIT_READY_MS, function()
        local buf = vim.fn.bufnr('COMMIT_EDITMSG')

        return buf > 0 and vim.fn.bufloaded(buf) == 1 and vim.bo[buf].modifiable
    end, 50)

    if ready ~= true then
        return { ok = false, error = 'commit buffer did not open' }
    end

    local buf = vim.fn.bufnr('COMMIT_EDITMSG')
    local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cut = #current

    for i, line in ipairs(current) do
        if line:match('^#') then
            cut = i - 1
            break
        end
    end

    local head = vim.list_extend({}, message)
    head[#head + 1] = ''
    vim.api.nvim_buf_set_lines(buf, 0, cut, false, head)

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
    end

    return { ok = true, subject = message[1] }
end

---@param files string[]
---@param root string
---@return nil
local function open_files(files, root)
    if #files == 0 then
        vim.cmd('edit ' .. vim.fn.fnameescape(root))
        return
    end

    local escaped = {}

    for i, file in ipairs(files) do
        escaped[i] = vim.fn.fnameescape(file)
    end

    vim.cmd('%argdelete')
    vim.cmd('args ' .. table.concat(escaped, ' '))
    vim.cmd('edit ' .. escaped[1])

    for i = 2, #files do
        vim.cmd('badd ' .. escaped[i])
    end
end

---@param line integer
---@param column integer?
---@return nil
local function place_cursor(line, column)
    local last = math.max(vim.api.nvim_buf_line_count(0), 1)
    local row = math.min(line, last)
    local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
    local col = math.min(math.max((column or 1) - 1, 0), #text)

    pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
end

---@param payload { files?: string[], items?: table[], root?: string, line?: integer, column?: integer }
---@return table
function M.edit(payload)
    local files = payload.files or {}
    local items = payload.items or {}
    local root = payload.root or vim.fn.getcwd()
    local line = tonumber(payload.line)
    local column = tonumber(payload.column)

    local result, err = view.call('edit', function()
        pcall(vim.fn.setreg, '/', '')
        pcall(vim.fn.histdel, 'search')
        pcall(vim.cmd, 'silent! nohlsearch')
        pcall(vim.cmd, 'silent! only')
        open_files(files, root)

        if #files == 1 and line and line >= 1 then
            place_cursor(line, column)
        end

        vim.fn.setqflist({}, 'r', { title = 'edit', items = items })

        if #items > 1 then
            vim.cmd('botright copen')
            vim.cmd('wincmd p')
        else
            vim.cmd('cclose')
        end

        pcall(vim.cmd, 'silent! nohlsearch')
        vim.cmd('redraw!')

        return true
    end)

    if err then
        return { ok = false, error = err }
    end

    return { ok = result == true, count = #files }
end

---@param payload { command?: string, view?: string }
---@return table
function M.command(payload)
    local command = payload.command or ''
    local name = payload.view or 'edit'

    if command == '' then
        return { ok = false, error = 'empty command' }
    end

    local result, err = view.call(name, function()
        vim.cmd(command)

        return {
            buffer = vim.api.nvim_buf_get_name(0),
        }
    end)

    if not result then
        return { ok = false, error = err or 'command returned no result' }
    end

    return {
        ok = true,
        view = name,
        buffer = result.buffer,
    }
end

---@param payload { base?: string, layout?: string, files?: string[], items?: table[], root?: string }
---@return table
function M.review(payload)
    local base = payload.base or ''
    local layout = payload.layout or 'unified'

    if base == '' then
        return { ok = false, error = 'missing base' }
    end

    if layout ~= 'unified' and layout ~= 'stacked' and layout ~= 'split' then
        layout = 'unified'
    end

    local _, err = view.call('vcs', function()
        vim.cmd('silent! only')
        vim.cmd('Diff review ++layout=' .. layout .. ' ' .. base)

        if layout ~= 'split' then
            vim.cmd('silent! only')
        end

        vim.cmd('redraw!')

        return true
    end)

    if err then
        return { ok = false, error = err }
    end

    return M.edit(payload)
end

local ops = {
    command = M.command,
    commit = M.commit,
    edit = M.edit,
    review = M.review,
}

---Entry point for muxlib.call: a payload file in, a JSON reply out.
---@param path string
---@return string
function M.rpc(path)
    local payload = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
        or {}
    local op = ops[payload.op]

    if not op then
        return vim.json.encode({
            ok = false,
            error = 'unknown op: ' .. tostring(payload.op),
        })
    end

    local ok, result = pcall(op, payload)

    if not ok then
        return vim.json.encode({ ok = false, error = tostring(result) })
    end

    return vim.json.encode(result)
end

return M
