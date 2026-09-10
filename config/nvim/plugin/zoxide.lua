local config = vim.g.zoxide or {}
vim.validate('vim.g.zoxide', config, 'table')

local log = vim.log.new({ name = 'zoxide', level = config.log_level })

local function fail(message)
    log.error(message)
    vim.notify('zoxide: ' .. message, vim.log.levels.ERROR)
end

local function run(args)
    local argv = vim.list_extend({ 'zoxide' }, args)
    local ok, process = pcall(vim.system, argv, { text = true })
    if not ok then
        return nil, tostring(process)
    end

    local result = process:wait(1000)
    log.debug(argv, result.code, result.stderr)
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

local function query(arg, list)
    local args = { 'query' }
    if list then
        args[#args + 1] = '--list'
    end
    args[#args + 1] = '--'
    vim.list_extend(args, vim.split(arg, '%s+', { trimempty = true }))
    return run(args)
end

local function open(opts)
    local arg = opts.args:gsub('\\(.)', '%1')
    local dir = vim.fs.abspath(arg)
    if vim.fn.isdirectory(dir) == 0 then
        local match, err = query(arg)
        if not match or match == '' then
            fail(err or 'no match found')
            return
        end
        dir = match
    end
    if vim.fn.isdirectory(dir) == 0 then
        fail('not a directory: ' .. dir)
        return
    end

    local ok, err = pcall(vim.api.nvim_cmd, {
        cmd = 'edit',
        args = { dir },
        magic = { file = false, bar = false },
        mods = opts.smods,
    }, {})
    if not ok then
        fail(tostring(err))
        return
    end

    local _, add_err = run({ 'add', '--', dir })
    if add_err then
        fail('could not record visit: ' .. add_err)
    end
end

local function complete(arg)
    local output, err = query(arg:gsub('\\(.)', '%1'), true)
    if not output then
        log.error('completion', err)
        return {}
    end

    return vim.tbl_map(
        vim.fn.fnameescape,
        vim.split(output, '\n', {
            plain = true,
            trimempty = true,
        })
    )
end

vim.api.nvim_create_user_command('Zoxide', open, {
    nargs = '_',
    bar = true,
    complete = complete,
    desc = 'open directory with zoxide',
})
