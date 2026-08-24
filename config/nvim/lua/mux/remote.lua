local M = {}

local RESOLVE_MS = 30000
local FORWARD_MS = 15000
local PROBE_MS = 2000

---The path expands in the remote shell, so `~` is that host's home, not ours.
local ENSURE = [[cd -- %s && nvim --headless -c 'lua local d, r = false, nil; ]]
    .. [[require("mux.server").ensure(vim.fn.getcwd(), function(s, e) r = s or { error = e }; d = true end); ]]
    .. [[vim.wait(25000, function() return d end, 50); ]]
    .. [[io.write(vim.json.encode(r or { error = "timed out" }))' -c qa]]

---@param host string
---@param args string[]
---@param timeout integer
---@return string? stdout
---@return string? err
local function ssh(host, args, timeout)
    local argv = { 'ssh', '-o', 'BatchMode=yes', host }
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true }):wait(timeout)
    if not res then
        return nil, ('ssh %s timed out'):format(host)
    end
    if res.code ~= 0 then
        local err = vim.trim(res.stderr or '')
        return nil, err ~= '' and err or ('ssh %s failed'):format(host)
    end
    return res.stdout
end

---@param socket string
---@return boolean
local function answers(socket)
    if not vim.uv.fs_stat(socket) then
        return false
    end
    local res = vim.system({
        vim.v.progpath,
        '--server',
        socket,
        '--remote-expr',
        '1',
    }, { text = true }):wait(PROBE_MS)
    return res ~= nil and res.code == 0
end

---@param path string
---@return string? path
---@return string? err
local function shell_safe(path)
    if path:find('[;&|`$\n\'"()<>]') then
        return nil, 'path has shell metacharacters: ' .. path
    end
    return path
end

---Start or reuse a server on `host` for `path`, forwarding its socket here.
---@param host string
---@param path string
---@param cb fun(server?: mux.Server, err?: string)
---@return nil
function M.ensure(host, path, cb)
    local server = require('mux.server')
    local safe, unsafe = shell_safe(path)
    if not safe then
        cb(nil, unsafe)
        return
    end
    local out, err = ssh(host, { ENSURE:format(safe) }, RESOLVE_MS)
    if not out then
        cb(nil, err)
        return
    end
    local ok, remote = pcall(vim.json.decode, vim.trim(out))
    if not ok or type(remote) ~= 'table' then
        cb(nil, ('%s gave no answer for %s'):format(host, path))
        return
    end
    if remote.error then
        cb(nil, ('%s: %s'):format(host, remote.error))
        return
    end
    local dir = ('%s/%s'):format(server.state().runtime_dir, host)
    local socket = ('%s/%s'):format(
        dir,
        vim.fn.fnamemodify(remote.socket, ':t')
    )
    local within, too_long = server.within_sun_path(socket)
    if not within then
        cb(nil, too_long)
        return
    end
    if not answers(socket) then
        vim.fn.mkdir(dir, 'p')
        vim.fn.delete(socket)
        local forward = vim.system({
            'ssh',
            '-f',
            '-N',
            '-o',
            'BatchMode=yes',
            '-o',
            'ExitOnForwardFailure=yes',
            '-o',
            'StreamLocalBindUnlink=yes',
            '-o',
            'ServerAliveInterval=30',
            '-o',
            'ServerAliveCountMax=3',
            '-L',
            ('%s:%s'):format(socket, remote.socket),
            host,
        }, { text = true }):wait(FORWARD_MS)
        if not forward or forward.code ~= 0 then
            cb(
                nil,
                ('cannot forward %s: %s'):format(
                    host,
                    forward and vim.trim(forward.stderr or '') or 'timed out'
                )
            )
            return
        end
    end
    cb({
        root = remote.root,
        session = remote.session,
        socket = socket,
        host = host,
    })
end

---Split an ssh-style `host:path` target, or report that it is a plain path.
---@param arg string
---@return string? host
---@return string? path
function M.split(arg)
    local host, path = arg:match('^([%w._-]+):(.*)$')
    if not host or vim.fn.isdirectory(arg) == 1 then
        return nil
    end
    return host, path ~= '' and path or '.'
end

return M
