local config = vim.g.zoxide or {}
vim.validate('vim.g.zoxide', config, 'table')

local M = {
    log = vim.log.new({ name = 'zoxide', level = config.log_level }),
}

local function decode(argv, result)
    M.log.debug(argv, result.code, result.stderr)
    if result.code ~= 0 then
        local err = vim.trim(result.stderr or ''):gsub('^zoxide: ', '')
        if err == '' then
            err = result.code == 124 and 'timed out'
                or ('exited with code ' .. result.code)
        end
        return nil, err
    end

    return ((result.stdout or ''):gsub('\n$', ''))
end

function M.run(args, cb)
    local argv = vim.list_extend({ 'zoxide' }, args)
    local on_exit = cb
            and vim.schedule_wrap(function(result)
                cb(decode(argv, result))
            end)
        or nil
    local ok, process =
        pcall(vim.system, argv, { text = true, timeout = 1000 }, on_exit)
    if not ok then
        local err = tostring(process)
        if cb then
            vim.schedule(function()
                cb(nil, err)
            end)
            return
        end
        return nil, err
    end

    if not cb then
        return decode(argv, process:wait(1000))
    end
end

function M.query(arg, list, cb)
    local args = { 'query' }
    if list then
        args[#args + 1] = '--list'
    end
    args[#args + 1] = '--'
    vim.list_extend(args, vim.split(arg, '%s+', { trimempty = true }))
    return M.run(args, cb)
end

return M
