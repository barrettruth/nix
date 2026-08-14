---@class mux.Server
---@field root string
---@field session string
---@field socket string

---@class mux.State
---@field server? mux.Server
---@field runtime_dir string
---@field state_dir string
---@field last_root? string

---@alias mux.EnsureCallback fun(server?: mux.Server, err?: string)

---@class mux.PendingEnsure
---@field callbacks mux.EnsureCallback[]
---@field timer? any
---@field proc? any

local M = {}

local ready = false
local setup_started = false
local setup_error

---@type mux.Server?
local current_server

---@type table<string, mux.PendingEnsure>
local pending = {}

local READY_TIMEOUT_MS = 5000
local READY_POLL_MS = 50
local LIST_PROBE_MS = 100
local ENSURE_PROBE_MS = 2000
local CONNECT_PROBE_MS = 200

---@return string
local function runtime_dir()
    local base = vim.env.XDG_RUNTIME_DIR
    if not base or base == '' then
        if vim.uv.os_uname().sysname == 'Darwin' then
            base = vim.env.TMPDIR or '/tmp'
        else
            base = '/run/user/' .. vim.uv.getuid()
        end
    end
    base = base:gsub('/+$', '')
    return base .. '/mux'
end

---@return string
local function state_dir()
    return vim.fn.stdpath('state') .. '/mux'
end

---@param root string
---@return boolean
local function has_marker(root)
    return vim.uv.fs_stat(root .. '/.git') ~= nil
        or vim.uv.fs_stat(root .. '/.jj') ~= nil
end

---@param root string?
---@return string? root
---@return string? err
local function validate_root(root)
    if type(root) ~= 'string' or root == '' then
        return nil, 'empty root'
    end
    local real = vim.uv.fs_realpath(root)
    if not real then
        return nil, 'invalid root: ' .. root
    end
    local stat = vim.uv.fs_stat(real)
    if not stat or stat.type ~= 'directory' then
        return nil, 'not a directory: ' .. real
    end
    if not has_marker(real) then
        return nil, 'invalid root: ' .. real
    end
    return real
end

---@param base string
---@return string
local function sanitize_base(base)
    base = base:gsub('[^A-Za-z0-9._-]', '_')
    base = base:gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if base == '' then
        return 'project'
    end
    return base
end

---@param s string
---@return string? hash
---@return string? err
local function cksum(s)
    local res = vim.system({ 'cksum' }, { text = true, stdin = s }):wait()
    if not res or res.code ~= 0 or not res.stdout then
        return nil, 'cksum failed'
    end
    return res.stdout:match('^(%d+)')
end

---@param root string
---@return string? stem
---@return string? err
local function stem(root)
    local hash, err = cksum(root)
    if not hash then
        return nil, err
    end
    return sanitize_base(vim.fn.fnamemodify(root, ':t')) .. '-' .. hash
end

---@param root string
---@return mux.Server? server
---@return string? err
local function paths_for(root)
    local name, err = stem(root)
    if not name then
        return nil, err
    end
    return {
        root = root,
        socket = runtime_dir() .. '/' .. name .. '.sock',
        session = state_dir() .. '/' .. name .. '.vim',
    }
end

---@param root string
---@param socket? string
---@return mux.Server? server
---@return string? err
local function server_for(root, socket)
    local paths, err = paths_for(root)
    if not paths then
        return nil, err
    end
    return {
        root = root,
        session = paths.session,
        socket = socket or paths.socket,
    }
end

---Return a non-strict snapshot of mux runtime and server state.
---@return mux.State
function M.state()
    return {
        server = current_server and {
            root = current_server.root,
            session = current_server.session,
            socket = current_server.socket,
        } or nil,
        runtime_dir = runtime_dir(),
        state_dir = state_dir(),
        last_root = vim.g.mux_last_root,
    }
end

---Return deterministic socket and session paths for a root.
---@param root string
---@return mux.Server? paths
---@return string? err
function M.paths(root)
    local real, err = validate_root(root)
    if not real then
        return nil, err
    end
    return paths_for(real)
end

---Serialize this server's readiness and identity for remote probes.
---@return string
function M.probe()
    if not setup_started then
        return vim.json.encode({ ok = false, error = 'not a mux server' })
    end
    if not ready then
        return vim.json.encode({
            ok = false,
            error = setup_error or 'not ready',
        })
    end
    return vim.json.encode({ ok = true, server = current_server })
end

local RPC_EXPR = "luaeval('require([[mux.server]]).probe()')"
local SET_LAST_ROOT_EXPR = "execute('let g:mux_last_root = ' . string(%s))"
local CLEAR_LAST_ROOT_EXPR =
    "luaeval('(function(root) if vim.g.mux_last_root == root then vim.g.mux_last_root = nil end return true end)(_A)', %s)"

---@param args string[]
---@param opts table
---@param cb? function
---@return any? proc
---@return string? err
local function spawn_nvim(args, opts, cb)
    local prog = vim.fn.executable(vim.v.progpath) == 1 and vim.v.progpath
        or 'nvim'
    local argv = { prog }
    local parent = vim.v.argv
    for i = 1, #parent - 1 do
        if parent[i] == '--cmd' then
            argv[#argv + 1] = '--cmd'
            argv[#argv + 1] = parent[i + 1]
        end
    end
    vim.list_extend(argv, args)
    local ok, proc = pcall(vim.system, argv, opts, cb)
    if ok then
        return proc
    end
    if prog ~= 'nvim' then
        argv[1] = 'nvim'
        ok, proc = pcall(vim.system, argv, opts, cb)
        if ok then
            return proc
        end
    end
    return nil, tostring(proc)
end

---@param socket string
---@param root string
---@param cb fun(err?: string)
---@param clear? boolean
local function set_remote_last_root(socket, root, cb, clear)
    local expr = (clear and CLEAR_LAST_ROOT_EXPR or SET_LAST_ROOT_EXPR):format(
        vim.fn.string(root)
    )
    local proc, err = spawn_nvim({
        '--server',
        socket,
        '--remote-expr',
        expr,
    }, { text = true, stdout = true, stderr = true }, function(res)
        vim.schedule(function()
            cb(res.code == 0 and nil or vim.trim(res.stderr or ''))
        end)
    end)
    if not proc then
        vim.schedule(function()
            cb(err)
        end)
    end
end

---@param stdout string?
---@return mux.Server? server
---@return string? err
local function decode_rpc(stdout)
    local raw = vim.trim(stdout or '')
    if raw == '' then
        return nil, 'empty response'
    end
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        return nil, 'invalid response'
    end
    if decoded.ok and type(decoded.server) == 'table' then
        return decoded.server
    end
    return nil, tostring(decoded.error or 'not ready')
end

---Synchronously ask a socket whether it is a ready mux server.
---@param socket string
---@param timeout? integer
---@return mux.Server? server
---@return string? err
local function probe_sync(socket, timeout)
    local proc, err = spawn_nvim({
        '--server',
        socket,
        '--remote-expr',
        RPC_EXPR,
    }, { text = true, stdout = true, stderr = true })
    if not proc then
        return nil, err
    end
    local res = proc:wait(timeout or LIST_PROBE_MS)
    if not res then
        pcall(proc.kill, proc, 15)
        return nil, 'timeout'
    end
    if res.code ~= 0 then
        return nil, vim.trim(res.stderr or '')
    end
    return decode_rpc(res.stdout)
end

---@param socket string
---@param timeout integer
---@param cb fun(server?: mux.Server, err?: string)
---@return nil
local function probe_async(socket, timeout, cb)
    local done = false
    local timer = vim.uv.new_timer()
    local proc
    ---@param server? mux.Server
    ---@param err? string
    local function finish(server, err)
        if done then
            return
        end
        done = true
        if timer then
            pcall(timer.stop, timer)
            pcall(timer.close, timer)
        end
        vim.schedule(function()
            cb(server, err)
        end)
    end
    local err
    proc, err = spawn_nvim({
        '--server',
        socket,
        '--remote-expr',
        RPC_EXPR,
    }, { text = true, stdout = true, stderr = true }, function(res)
        if res.code ~= 0 then
            finish(nil, vim.trim(res.stderr or ''))
            return
        end
        local server, rpc_err = decode_rpc(res.stdout)
        finish(server, rpc_err)
    end)
    if not proc then
        finish(nil, err)
        return
    end
    timer:start(timeout, 0, function()
        pcall(proc.kill, proc, 15)
        finish(nil, 'timeout')
    end)
end

---@param socket string
---@param cb fun(listening: boolean)
---@return nil
local function socket_listening_async(socket, cb)
    if not vim.uv.fs_stat(socket) then
        vim.schedule(function()
            cb(false)
        end)
        return
    end
    local ok, pipe = pcall(vim.uv.new_pipe, false)
    if not ok or not pipe then
        vim.schedule(function()
            cb(false)
        end)
        return
    end
    local timer = vim.uv.new_timer()
    local done = false
    ---@param alive boolean
    ---@return nil
    local function finish(alive)
        if done then
            return
        end
        done = true
        pcall(timer.stop, timer)
        pcall(timer.close, timer)
        pcall(function()
            pipe:close()
        end)
        vim.schedule(function()
            cb(alive)
        end)
    end
    timer:start(CONNECT_PROBE_MS, 0, function()
        finish(false)
    end)
    pcall(function()
        pipe:connect(socket, function(err)
            finish(err == nil)
        end)
    end)
end

---Report whether a socket path currently has a listener bound to it.
---A stale socket file left by a dead server refuses the connection; a live but
---busy server accepts it, so this distinguishes "gone" from "not answering yet".
---@param socket string
---@return boolean
local function socket_listening(socket)
    local done, alive = false, false
    socket_listening_async(socket, function(listening)
        alive, done = listening, true
    end)
    vim.wait(CONNECT_PROBE_MS + READY_POLL_MS, function()
        return done
    end, 10)
    return alive
end

---@param out mux.Server[]
---@param seen table<string, boolean>
---@param server mux.Server?
---@return nil
local function add_server(out, seen, server)
    if not server or seen[server.root] then
        return
    end
    seen[server.root] = true
    out[#out + 1] = server
end

---@param file string
---@return string? root
local function saved_root(file)
    for _, line in ipairs(vim.fn.readfile(file, '', 20)) do
        local expr = line:match('^let Mux = (.+)$')
        if expr then
            local mux = vim.json.decode(vim.fn.eval(expr))
            return validate_root(mux.root)
        end
    end
end

---List mux servers that answer readiness probes.
---@return mux.Server[]
function M.list()
    local out = {}
    local seen = {}
    local sockets = vim.fn.glob(runtime_dir() .. '/*.sock', true, true)
    table.sort(sockets)
    for _, socket in ipairs(sockets) do
        if current_server and socket == current_server.socket then
            add_server(out, seen, current_server)
        else
            add_server(out, seen, probe_sync(socket, LIST_PROBE_MS))
        end
    end
    local sessions = vim.fn.glob(state_dir() .. '/*.vim', true, true)
    table.sort(sessions)
    for _, file in ipairs(sessions) do
        local root = saved_root(file)
        add_server(out, seen, root and paths_for(root))
    end
    return out
end

---@param path string
---@param root string
---@return boolean
local function contains(path, root)
    if path == root then
        return true
    end
    return vim.startswith(path, root .. '/')
end

---Find the most specific known mux server containing a path.
---@param path string
---@return mux.Server? server
---@return string? err
function M.find(path)
    if type(path) ~= 'string' or path == '' then
        return nil, 'empty path'
    end
    local real = vim.uv.fs_realpath(path)
        or vim.uv.fs_realpath(vim.fn.fnamemodify(path, ':h'))
    if not real then
        return nil, 'invalid path: ' .. path
    end
    local best
    for _, server in ipairs(M.list()) do
        if
            contains(real, server.root)
            and (not best or #server.root > #best.root)
        then
            best = server
        end
    end
    return best
end

---@param root string
---@param server? mux.Server
---@param err? string
---@return nil
local function finish_pending(root, server, err)
    if vim.in_fast_event() then
        vim.schedule(function()
            finish_pending(root, server, err)
        end)
        return
    end
    local entry = pending[root]
    pending[root] = nil
    if not entry then
        return
    end
    if entry.timer then
        pcall(entry.timer.stop, entry.timer)
        pcall(entry.timer.close, entry.timer)
    end
    for _, cb in ipairs(entry.callbacks) do
        local ok, cb_err = pcall(cb, server, err)
        if not ok then
            vim.notify(
                'mux: ensure callback failed: ' .. tostring(cb_err),
                vim.log.levels.ERROR
            )
        end
    end
end

---Start or reuse the mux server for a validated project root.
---@param root string
---@param cb mux.EnsureCallback
---@return nil
function M.ensure(root, cb)
    local real, err = validate_root(root)
    if not real then
        vim.schedule(function()
            cb(nil, err)
        end)
        return
    end
    if pending[real] then
        pending[real].callbacks[#pending[real].callbacks + 1] = cb
        return
    end
    local paths, perr = paths_for(real)
    if not paths then
        vim.schedule(function()
            cb(nil, perr)
        end)
        return
    end
    local existing, probe_err = probe_sync(paths.socket, LIST_PROBE_MS)
    if not existing and socket_listening(paths.socket) then
        existing, probe_err = probe_sync(paths.socket, ENSURE_PROBE_MS)
        if not existing then
            local reason = probe_err and probe_err ~= '' and probe_err
                or 'no response'
            vim.schedule(function()
                cb(
                    nil,
                    ('socket in use by an unresponsive server: %s (%s)'):format(
                        paths.socket,
                        reason
                    )
                )
            end)
            return
        end
    end
    if existing then
        if existing.root ~= real then
            vim.schedule(function()
                cb(nil, 'socket belongs to different root: ' .. paths.socket)
            end)
            return
        end
        vim.schedule(function()
            cb(existing)
        end)
        return
    end
    if vim.uv.fs_stat(paths.socket) ~= nil then
        pcall(vim.fn.delete, paths.socket)
    end
    pcall(vim.fn.mkdir, runtime_dir(), 'p')
    pcall(vim.fn.mkdir, state_dir(), 'p')
    pending[real] = { callbacks = { cb } }
    local proc, spawn_err = spawn_nvim({
        '--headless',
        '--listen',
        paths.socket,
        '+lua require("mux.server").setup()',
    }, {
        cwd = real,
        detach = true,
        stdout = false,
        stderr = false,
    })
    if not proc then
        finish_pending(real, nil, spawn_err)
        return
    end
    pending[real].proc = proc
    local started = vim.uv.now()
    ---@return nil
    local function poll()
        local entry = pending[real]
        if not entry then
            return
        end
        if entry.timer then
            local timer = entry.timer
            entry.timer = nil
            pcall(timer.stop, timer)
            pcall(timer.close, timer)
        end
        if vim.uv.now() - started >= READY_TIMEOUT_MS then
            pcall(proc.kill, proc, 15)
            finish_pending(real, nil, 'server startup timed out: ' .. real)
            return
        end
        ---@return nil
        local function reschedule()
            local entry2 = pending[real]
            if not entry2 then
                return
            end
            entry2.timer = vim.uv.new_timer()
            entry2.timer:start(READY_POLL_MS, 0, poll)
        end
        socket_listening_async(paths.socket, function(listening)
            if not listening then
                reschedule()
                return
            end
            probe_async(paths.socket, LIST_PROBE_MS, function(server, rerr)
                if server then
                    if server.root == real then
                        finish_pending(real, server)
                    else
                        finish_pending(
                            real,
                            nil,
                            'socket belongs to different root: ' .. paths.socket
                        )
                    end
                    return
                end
                if
                    rerr
                    and rerr ~= ''
                    and rerr ~= 'not ready'
                    and rerr ~= 'timeout'
                then
                    finish_pending(real, nil, rerr)
                    return
                end
                reschedule()
            end)
        end)
    end
    poll()
end

---Connect this UI to a mux root, recording the current root on the target.
---@param root string
---@param cb? fun(ok?: true, err?: string)
---@param clear_last? boolean
---@return nil
function M.connect(root, cb, clear_last)
    cb = cb or function() end
    local current = current_server
    M.ensure(root, function(target_server, ensure_err)
        if not target_server then
            cb(nil, ensure_err)
            return
        end
        if current and current.root == target_server.root then
            cb(true)
            return
        end
        local function connect()
            local ok, connect_err = pcall(
                vim.cmd,
                'connect ' .. vim.fn.fnameescape(target_server.socket)
            )
            if not ok then
                cb(nil, tostring(connect_err))
                return
            end
            cb(true)
        end
        local function connect_when_ready()
            if #vim.api.nvim_list_uis() > 0 then
                connect()
                return
            end
            vim.api.nvim_create_autocmd('UIEnter', {
                group = vim.api.nvim_create_augroup(
                    'mux-connect',
                    { clear = true }
                ),
                once = true,
                callback = connect,
            })
        end
        if current and current.root ~= target_server.root then
            set_remote_last_root(target_server.socket, current.root, function()
                connect_when_ready()
            end, clear_last)
            return
        end
        connect_when_ready()
    end)
end

---Save the user session before restarting this mux server.
---@return true? ok
---@return string? err
function M.reload()
    local session = require('mux.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end
    vim.schedule(function()
        vim.cmd('restart! +qall!')
    end)
    return true
end

---Initialize this process as the mux server for its cwd.
---@return true? ok
---@return string? err
function M.setup()
    if setup_started then
        return true
    end
    setup_started = true
    local root, err = validate_root(vim.fn.getcwd())
    if not root then
        setup_error = err
        return nil, err
    end
    local server, serr = server_for(root, vim.v.servername)
    if not server then
        setup_error = serr
        return nil, serr
    end
    current_server = server
    vim.o.sessionoptions =
        'buffers,curdir,folds,globals,help,tabpages,winsize,winpos'
    require('mux.session').setup()
    require('mux.view').setup()
    require('mux.line').setup()
    local ok, rerr = require('mux.session').restore()
    if not ok and rerr ~= 'no session' then
        setup_error = rerr
        return nil, rerr
    end
    if not ok then
        require('mux.view').restore()
    end
    ready = true
    require('mux.line').refresh()
    return true
end

M._validate_root = validate_root
M._paths_for = paths_for
return M
