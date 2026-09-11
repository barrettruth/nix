local zoxide = require('zoxide')
local log = zoxide.log

local function fail(message)
    log.error(message)
    vim.notify('zoxide: ' .. message, vim.log.levels.ERROR)
end

local function open(opts)
    local arg = opts.args:gsub('\\(.)', '%1')
    local dir = vim.fs.abspath(arg)
    if vim.fn.isdirectory(dir) == 0 then
        local match, err = zoxide.query(arg)
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
        cmd = 'split',
        args = { dir },
        magic = { file = false, bar = false },
        mods = opts.smods,
    }, {})
    if not ok then
        fail(tostring(err))
        return
    end

    local _, add_err = zoxide.run({ 'add', '--', dir })
    if add_err then
        fail('could not record visit: ' .. add_err)
    end
end

local function complete(arg)
    local output, err = zoxide.query(arg:gsub('\\(.)', '%1'), true)
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
    desc = 'open directory in a split with zoxide',
})
