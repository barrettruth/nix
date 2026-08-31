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

---@param arg string
---@return string? root
---@return string? err
function M.resolve(arg)
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

---@param arg string?
---@param cb mux.EnsureCallback
---@return nil
function M.ensure(arg, cb)
    arg = vim.trim(arg or '')
    local host, path = require('mux.remote').split(arg)
    if host then
        require('mux.remote').ensure(host, path, cb)
        return
    end

    local root, err = M.resolve(arg)
    if not root then
        cb(nil, err)
        return
    end

    server.ensure_target(root, cb)
end

---Connect this UI to the mux server for a resolved project root.
---@param arg string?
---@return nil
function M.mux(arg)
    arg = vim.trim(arg or '')

    if arg == '' then
        local target = server.ordered()[1]
        if target then
            server.switch(target, done)
            return
        end
    end

    M.ensure(arg, function(target, err)
        if not target then
            done(nil, err)
            return
        end

        server.switch(target, done)
    end)
end

return M
