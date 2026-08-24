local M = {}

local RESOLVE_MS = 10000
local FORWARD_MS = 10000

---@param fmt string
---@param ... any
local function log(fmt, ...)
    local dir = vim.fn.stdpath('log')
    vim.fn.mkdir(dir, 'p')
    local line = ('%s [mux]: %s'):format(
        os.date('%Y-%m-%d %H:%M:%S'),
        fmt:format(...)
    )
    pcall(vim.fn.writefile, { line }, dir .. '/mux.log', 'a')
end

---@param started integer
---@return integer
local function since(started)
    return math.floor((vim.uv.hrtime() - started) / 1e6)
end

local CONNECT_TIMEOUT = 'ConnectTimeout=5'

local ENSURE = [[cd -- %s && nvim --headless -c 'lua local d, r = false, nil; ]]
    .. [[require("mux.server").ensure(vim.fn.getcwd(), function(s, e) r = s or { error = e }; d = true end); ]]
    .. [[vim.wait(25000, function() return d end, 50); ]]
    .. [[io.write(vim.json.encode(r or { error = "timed out" }))' -c qa]]

---One multiplexed connection per host holds every forward to it, so opening a
---second project there costs no handshake and leaks no second process.
---@param host string
---@return string[]
local function control(host)
    local path = ('%s/ssh-%s'):format(
        require('mux.server').state().runtime_dir,
        host
    )

    return {
        '-o',
        'ControlMaster=auto',
        '-o',
        ('ControlPath=%s'):format(path),
        '-o',
        'ControlPersist=yes',
    }
end

---@param host string
---@param args string[]
---@param timeout integer
---@return string? stdout
---@return string? err
local function ssh(host, args, timeout)
    local argv = { 'ssh', '-o', 'BatchMode=yes', '-o', CONNECT_TIMEOUT }
    vim.list_extend(argv, control(host))
    argv[#argv + 1] = host
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true }):wait(timeout)
    if not res then
        return nil, ('ssh %s timed out'):format(host)
    end

    if res.code ~= 0 then
        local lines =
            vim.split(vim.trim(res.stderr or ''), '\n', { trimempty = true })
        local err = lines[#lines]

        return nil, err and vim.trim(err) or ('ssh %s failed'):format(host)
    end

    return res.stdout
end

local function quote(s)
    return ("'%s'"):format(s:gsub("'", "'\\''"))
end

---A leading `~` stays bare so the remote shell still expands it.
local function shell_quote(path)
    local tilde, rest = path:match('^(~[^/]*)/(.*)$')

    if tilde then
        return ('%s/%s'):format(tilde, quote(rest))
    end

    if path:match('^~[^/]*$') then
        return path
    end

    return quote(path)
end

---@param host string
---@param socket string
---@param remote_socket string
---@return string? err
local function forward(host, socket, remote_socket)
    local started = vim.uv.hrtime()
    local spec = ('%s:%s'):format(socket, remote_socket)
    local shared = {
        'ssh',
        '-o',
        'BatchMode=yes',
        '-o',
        CONNECT_TIMEOUT,
        '-o',
        'StreamLocalBindUnlink=yes',
    }

    local drop = vim.list_extend(vim.deepcopy(shared), control(host))
    vim.list_extend(drop, { '-O', 'cancel', '-L', spec, host })
    vim.system(drop, { text = true }):wait(FORWARD_MS)

    local argv = vim.list_extend(vim.deepcopy(shared), control(host))
    vim.list_extend(argv, { '-O', 'forward', '-L', spec, host })
    local res = vim.system(argv, { text = true }):wait(FORWARD_MS)

    if res and res.code == 0 then
        log('%s forward mux %s %dms', host, socket, since(started))
        return nil
    end

    local own = vim.list_extend(vim.deepcopy(shared), {
        '-f',
        '-N',
        '-o',
        'ExitOnForwardFailure=yes',
        '-o',
        'ServerAliveInterval=30',
        '-o',
        'ServerAliveCountMax=3',
        '-L',
        spec,
        host,
    })
    local fallback = vim.system(own, { text = true }):wait(FORWARD_MS)

    if fallback and fallback.code == 0 then
        log('%s forward own %s %dms', host, socket, since(started))
        return nil
    end

    local err = fallback and vim.trim(fallback.stderr or '') or 'timed out'
    log('%s forward failed %dms: %s', host, since(started), err)

    return err
end

---Start or reuse a server on `host` for `path`, forwarding its socket here.
---@param host string
---@param path string
---@param cb fun(server?: mux.Server, err?: string)
---@return nil
function M.ensure(host, path, cb)
    local server = require('mux.server')
    local started = vim.uv.hrtime()
    log('%s ensure %s', host, path)
    local out, err = ssh(host, { ENSURE:format(shell_quote(path)) }, RESOLVE_MS)

    if not out then
        log('%s resolve failed %dms: %s', host, since(started), err)
        cb(nil, err)
        return
    end

    local ok, remote = pcall(vim.json.decode, vim.trim(out))

    if not ok or type(remote) ~= 'table' then
        log('%s resolve failed %dms: no answer', host, since(started))
        cb(nil, ('%s gave no answer for %s'):format(host, path))
        return
    end

    if remote.error then
        log('%s resolve failed %dms: %s', host, since(started), remote.error)
        cb(nil, ('%s: %s'):format(host, remote.error))
        return
    end

    log('%s resolved %s %dms', host, remote.root, since(started))

    local dir = ('%s/%s'):format(server.state().runtime_dir, host)
    local socket = ('%s/%s'):format(
        dir,
        vim.fn.fnamemodify(remote.socket, ':t')
    )
    local within, too_long = server.within_sun_path(socket)

    if not within then
        log('%s %s', host, too_long)
        cb(nil, too_long)
        return
    end

    if not server.socket_listening(socket) then
        vim.fn.mkdir(dir, 'p')
        vim.fn.delete(socket)
        local ferr = forward(host, socket, remote.socket)

        if ferr then
            cb(nil, ('cannot forward %s: %s'):format(host, ferr))
            return
        end

        if
            not vim.wait(FORWARD_MS, function()
                return server.socket_listening(socket)
            end, 100)
        then
            log('%s forward never answered %s', host, socket)
            cb(nil, ('%s forwarded but never answered'):format(host))
            return
        end
    else
        log('%s forward reused %s', host, socket)
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
