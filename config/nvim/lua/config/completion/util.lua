---@class config.completion.util
local M = {}

---@param base string
---@return config.completion.Context
function M.context(base)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local col = cursor[2]
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

---@param text string
---@return string[]
function M.lines(text)
    local lines = {}

    for line in (text .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end

    return lines
end

---@param text string
---@param prefix string
---@return boolean
function M.starts_with(text, prefix)
    return prefix == '' or text:sub(1, #prefix) == prefix
end

---@param text string
---@param prefix string
---@return boolean
function M.starts_with_icase(text, prefix)
    return prefix == '' or text:sub(1, #prefix):lower() == prefix:lower()
end

---@param values string[]
---@param base string
---@param ignore_case? boolean
---@return string[]
function M.filter_strings(values, base, ignore_case)
    if base == '' then
        return values
    end

    local filtered = {}

    for _, value in ipairs(values) do
        local matches = ignore_case and M.starts_with_icase(value, base)
            or M.starts_with(value, base)
        if matches then
            filtered[#filtered + 1] = value
        end
    end

    return filtered
end

---@param items config.completion.Items
---@param base string
---@return config.completion.Items
function M.filter_items(items, base)
    if base == '' then
        return items
    end

    local filtered = {}

    for _, item in ipairs(items) do
        local matches = item.icase == 1 and M.starts_with_icase(item.word, base)
            or M.starts_with(item.word, base)
        if matches then
            filtered[#filtered + 1] = item
        end
    end

    return filtered
end

---@generic T
---@param fn fun(...): T
---@param fallback T
---@param ... any
---@return T
function M.safe_call(fn, fallback, ...)
    local ok, value = pcall(fn, ...)
    if ok then
        return value
    end

    return fallback
end

---@param binary string
---@return boolean
function M.executable(binary)
    return vim.fn.executable(binary) == 1
end

---@param command string[]
---@return string
function M.system_text(command)
    local result = vim.system(command):wait()

    return result.stdout or ''
end

---Resolve the git toplevel for a directory. Empty string if no git context.
---@param dir? string
---@return string
function M.git_root(dir)
    if not dir or dir == '' then
        dir = vim.uv.cwd() or '.'
    end
    return vim.fs.root(dir, '.git') or ''
end

---@param command string[]
---@param callback fun(stdout: string)
function M.system_text_async(command, callback)
    vim.system(command, {}, function(result)
        callback(result.stdout or '')
    end)
end

---@param binary string
---@param command string[]
---@return config.completion.LoaderTask
function M.system_task(binary, command)
    return {
        sync = function()
            if not M.executable(binary) then
                return ''
            end

            return M.system_text(command)
        end,
        async = function(done)
            if not M.executable(binary) then
                done('')
                return
            end

            M.system_text_async(command, done)
        end,
    }
end

---@param path? string
---@return string
function M.read_file(path)
    if not path or path == '' then
        return ''
    end

    local file = io.open(path, 'r')
    if not file then
        return ''
    end

    local content = file:read('*a') or ''
    file:close()

    return content
end

---@param path? string
---@param callback fun(content: string)
function M.read_file_async(path, callback)
    if not path or path == '' then
        callback('')
        return
    end

    vim.uv.fs_open(path, 'r', 438, function(open_err, fd)
        if open_err or not fd then
            callback('')
            return
        end

        vim.uv.fs_fstat(fd, function(stat_err, stat)
            if stat_err or not stat then
                vim.uv.fs_close(fd, function()
                    callback('')
                end)
                return
            end

            vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
                vim.uv.fs_close(fd, function()
                    if read_err or type(data) ~= 'string' then
                        callback('')
                        return
                    end

                    callback(data)
                end)
            end)
        end)
    end)
end

---@param path fun(): string?
---@return config.completion.LoaderTask
function M.file_task(path)
    return {
        sync = function()
            return M.read_file(path())
        end,
        async = function(done)
            M.read_file_async(path(), done)
        end,
    }
end

return M
