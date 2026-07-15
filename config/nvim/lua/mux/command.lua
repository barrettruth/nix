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
---@return nil
function M.mux(arg)
    local root, err = resolve_arg(arg)
    if not root then
        vim.notify('mux: ' .. err, vim.log.levels.ERROR)
        return
    end
    local current = require('mux.server').state().server
    if current and current.root == root then
        return
    end
    require('mux.server').ensure(root, function(server, ensure_err)
        if not server then
            vim.notify(
                'mux: '
                    .. (ensure_err or ('server startup timed out: ' .. root)),
                vim.log.levels.ERROR
            )
            return
        end
        local ok, connect_err =
            pcall(vim.cmd, 'connect ' .. vim.fn.fnameescape(server.socket))
        if not ok then
            vim.notify('mux: ' .. tostring(connect_err), vim.log.levels.ERROR)
        end
    end)
end

return M
