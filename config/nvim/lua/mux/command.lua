local M = {}

local function has_marker(path)
    return vim.uv.fs_stat(path .. '/.git') ~= nil
        or vim.uv.fs_stat(path .. '/.jj') ~= nil
end

local function resolve_arg(arg)
    local raw = vim.trim(arg or '')
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
        for _, server in ipairs(require('mux.server').list()) do
            if server.root == raw then
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
    local root, err
    local target
    local host, path = require('mux.remote').split(vim.trim(arg or ''))
    if host then
        require('mux.remote').ensure(host, path, function(server, remote_err)
            if not server then
                vim.notify(
                    'mux: ' .. tostring(remote_err),
                    vim.log.levels.ERROR
                )
                return
            end

            require('mux.server').attach(server, function(ok, attach_err)
                if not ok then
                    vim.notify(
                        'mux: ' .. tostring(attach_err),
                        vim.log.levels.ERROR
                    )
                end
            end)
        end)
        return
    end

    if vim.trim(arg or '') == '' then
        target = require('mux.line').servers()[1]
        root = target and target.root
    end

    if not root then
        root, err = resolve_arg(arg)
    end

    if not root then
        vim.notify('mux: ' .. err, vim.log.levels.ERROR)
        return
    end

    local server = require('mux.server')
    local connect = target and server.switch or server.connect
    connect(target or root, function(ok, connect_err)
        if not ok then
            vim.notify('mux: ' .. tostring(connect_err), vim.log.levels.ERROR)
        end
    end)
end

return M
