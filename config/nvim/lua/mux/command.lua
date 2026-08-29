local server = require('mux.server')

local M = {}

local function done(ok, err)
    if not ok then
        vim.notify('mux: ' .. tostring(err), vim.log.levels.ERROR)
    end
end

local function has_marker(path)
    return vim.uv.fs_stat(path .. '/.git') ~= nil
        or vim.uv.fs_stat(path .. '/.jj') ~= nil
end

local function resolve_arg(arg)
    local raw = arg
    if raw == '' then
        raw = vim.fn.getcwd()
    else
        raw = vim.fn.expand(raw)
        if not raw:match('^/') then
            raw = vim.fn.getcwd() .. '/' .. raw
        end
    end

    local real = vim.uv.fs_realpath(raw)
    if not real then
        for _, entry in ipairs(server.list()) do
            if entry.root == raw then
                return raw
            end
        end
        return nil, 'path does not exist: ' .. raw
    end

    local stat = vim.uv.fs_stat(real)
    if stat and stat.type == 'file' then
        real = vim.fn.fnamemodify(real, ':h')
    end

    while real and real ~= '' do
        if has_marker(real) then
            return real
        end

        local parent = vim.fn.fnamemodify(real, ':h')
        if parent == real then
            break
        end

        real = parent
    end

    return nil, 'no git/jj root: ' .. raw
end

---Connect this UI to the mux server for a resolved project root.
---@param arg string?
---@return nil
function M.mux(arg)
    arg = vim.trim(arg or '')
    local root, err
    local host, path = require('mux.remote').split(arg)
    if host then
        require('mux.remote').ensure(host, path, function(target, remote_err)
            if not target then
                done(nil, remote_err)
                return
            end

            server.switch(target, done)
        end)
        return
    end

    if arg == '' then
        local target = server.ordered()[1]
        if target then
            server.switch(target, done)
            return
        end
    end

    if not root then
        root, err = resolve_arg(arg)
    end

    if not root then
        done(nil, err)
        return
    end

    server.connect(root, done)
end

return M
