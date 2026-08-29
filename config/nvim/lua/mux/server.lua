---@class mux.Server
---@field root string
---@field session string
---@field socket string
---@field host? string

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
local CONNECT_PROBE_MS = 1000

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

---Whether a socket is one this machine hands out.
---@param socket string
---@return boolean
local function ours(socket)
    return vim.startswith(socket, runtime_dir() .. '/')
end

---@param socket string
---@return string? host
local function host_of(socket)
    local dir = vim.fn.fnamemodify(socket, ':h')
    if dir == runtime_dir() then
        return nil
    end

    return vim.fn.fnamemodify(dir, ':t')
end

---@param socket string
---@return string? socket
---@return string? err
local function within_sun_path(socket)
    local limit = vim.uv.os_uname().sysname == 'Darwin' and 104 or 108
    if #socket > limit then
        return nil,
            ('socket path too long: %s (%d bytes, max %d)'):format(
                socket,
                #socket,
                limit
            )
    end

    return socket
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

---@type table<string, string>
local stems = {}

---Memoised: a root's stem never changes, and every miss spawns cksum.
---@param root string
---@return string? stem
---@return string? err
local function stem(root)
    if stems[root] then
        return stems[root]
    end

    local hash, err = cksum(root)
    if not hash then
        return nil, err
    end

    stems[root] = sanitize_base(vim.fn.fnamemodify(root, ':t')) .. '-' .. hash

    return stems[root]
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
local SET_THEME_EXPR = "execute('colorscheme ' . %s)"
local SET_PEERS_EXPR =
    "luaeval('(function(p) vim.g.mux_peers = p; require([[mux.line]]).refresh(); return true end)(_A)', %s)"
local RESTARTED_EXPR =
    "luaeval('(function(m) vim.api.nvim_create_autocmd([[UIEnter]], { once = true, callback = function() vim.defer_fn(function() vim.api.nvim_echo({ { m } }, true, {}) end, 50) end }); return true end)(_A)', %s)"

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
            if res.code == 0 then
                cb()
                return
            end

            cb(vim.trim(res.stderr or ''))
        end)
    end)
    if not proc then
        vim.schedule(function()
            cb(err)
        end)
    end
end

---Hand a target the caller's view of every server, addressed as the caller
---reaches them: `:connect` is performed by the UI client, not by its server.
---@param target mux.Server
---@param cb fun(err?: string)
local function push_peers(target, cb)
    local list = M.list()
    -- A forwarded socket costs a round trip, so the probe budget can miss one
    -- we already know is live.
    if
        not vim.iter(list):any(function(s)
            return s.root == target.root
        end)
    then
        list[#list + 1] = target
    end

    local expr = SET_PEERS_EXPR:format(vim.fn.string(vim.json.encode(list)))
    local proc, err = spawn_nvim({
        '--server',
        target.socket,
        '--remote-expr',
        expr,
    }, { text = true, stdout = true, stderr = true }, function(res)
        vim.schedule(function()
            if res.code == 0 then
                cb()
                return
            end

            cb(vim.trim(res.stderr or ''))
        end)
    end)
    if not proc then
        vim.schedule(function()
            cb(err)
        end)
    end
end

---@return mux.Server[]
local function peers()
    local raw = vim.g.mux_peers

    return raw and vim.json.decode(raw) or {}
end

---@param root string
---@return mux.Server? peer
local function peer_for(root)
    for _, peer in ipairs(peers()) do
        if peer.root == root then
            return peer
        end
    end
end

---@param stdout string?
---@param socket string
---@return mux.Server? server
---@return string? err
local function decode_rpc(stdout, socket)
    local raw = vim.trim(stdout or '')
    if raw == '' then
        return nil, 'empty response'
    end

    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        return nil, 'invalid response'
    end

    if decoded.ok and type(decoded.server) == 'table' then
        decoded.server.socket = socket
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

    return decode_rpc(res.stdout, socket)
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
            timer:stop()
            timer:close()
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

        local server, rpc_err = decode_rpc(res.stdout, socket)
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
        timer:stop()
        timer:close()
        pipe:close()
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

---List known mux servers: peers the connecting UI told us about, then saved
---sessions, then live sockets not yet saved. Peers rank first because only the
---UI client's own addresses are ones it can reach; sessions precede sockets so
---their sockets need no probe, probing waiting on a subprocess and vim.wait()
---flushing the screen from the pre-refresh cache. A peer is a snapshot that
---outlives the server it names, so an address of ours must still be there; a
---session and a socket are removed by the server that owned them.
---@return mux.Server[]
function M.list()
    local out = {}
    local seen = {}
    local known = {}

    for _, peer in ipairs(peers()) do
        if not ours(peer.socket) or vim.uv.fs_stat(peer.socket) then
            add_server(out, seen, peer)
        end
    end

    local sessions = vim.fn.glob(state_dir() .. '/*.vim', true, true)
    table.sort(sessions)

    for _, file in ipairs(sessions) do
        local root = saved_root(file)
        local server = root and paths_for(root)

        if server then
            known[server.socket] = true
            add_server(out, seen, server)
        end
    end

    local sockets = vim.fn.glob(runtime_dir() .. '/*.sock', true, true)
    vim.list_extend(
        sockets,
        vim.fn.glob(runtime_dir() .. '/*/*.sock', true, true)
    )
    table.sort(sockets)

    for _, socket in ipairs(sockets) do
        local live = current_server and socket == current_server.socket

        if not known[socket] then
            local server = live and current_server
                or probe_sync(socket, LIST_PROBE_MS)
            if server then
                server.host = host_of(socket)
            end

            add_server(out, seen, server)
        end
    end

    return out
end

---@return mux.Server[]
function M.ordered()
    local servers = M.list()
    table.sort(servers, function(a, b)
        return a.root < b.root
    end)

    return servers
end

---@param root string
---@param server? mux.Server
---@param err? string
---@return nil
local function finish_pending(root, server, err)
    vim.schedule(function()
        local entry = pending[root]
        pending[root] = nil

        if not entry then
            return
        end

        if entry.timer then
            entry.timer:stop()
            entry.timer:close()
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
    end)
end

---Start or reuse the mux server for a project root.
---@param root string
---@param cb mux.EnsureCallback
---@return nil
function M.ensure(root, cb)
    if pending[root] then
        pending[root].callbacks[#pending[root].callbacks + 1] = cb
        return
    end

    local peer = peer_for(root)

    if peer and peer.host then
        require('mux.remote').ensure(peer.host, root, cb)
        return
    end

    local paths, perr = paths_for(root)
    if not paths then
        vim.schedule(function()
            cb(nil, perr)
        end)
        return
    end

    local existing, probe_err = probe_sync(paths.socket, LIST_PROBE_MS)
    if not existing and socket_listening(paths.socket) then
        existing, probe_err = probe_sync(paths.socket, 2000)
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
        if existing.root ~= root then
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

    local real, err = validate_root(root)
    if not real then
        vim.schedule(function()
            cb(nil, err)
        end)
        return
    end

    if real ~= root then
        M.ensure(real, cb)
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
        ('+lua require("mux.server").setup(%q)'):format(real),
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
            timer:stop()
            timer:close()
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

---Connect this UI to a running server, recording the current root on it.
---@param target_server mux.Server
---@param cb? fun(ok?: true, err?: string)
---@param clear_last? boolean
---@return nil
function M.attach(target_server, cb, clear_last)
    cb = cb or function() end
    local current = current_server
    if current and current.root == target_server.root then
        cb(true)
        return
    end

    local function connect()
        -- A UI that is not itself a mux server was started only to reach one,
        -- and the server it detaches from has nothing else to end it.
        local ok, connect_err = pcall(vim.cmd.connect, {
            vim.fn.fnameescape(target_server.socket),
            bang = not current,
        })
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

    -- Connecting a UI to an address nothing answers exits it, but only our own
    -- sockets are ours to judge: the rest are addressed for the UI client.
    local judged = ours(target_server.socket)
    push_peers(target_server, function(push_err)
        if push_err and judged then
            cb(
                nil,
                ('cannot reach %s: %s'):format(target_server.root, push_err)
            )
            return
        end

        if not current then
            connect_when_ready()
            return
        end

        set_remote_last_root(target_server.socket, current.root, function()
            connect_when_ready()
        end, clear_last)
    end)
end

---Start or reuse the server for a root, then connect this UI to it.
---@param root string
---@param cb? fun(ok?: true, err?: string)
---@param clear_last? boolean
---@return nil
function M.connect(root, cb, clear_last)
    cb = cb or function() end
    M.ensure(root, function(target_server, ensure_err)
        if not target_server then
            cb(nil, ensure_err)
            return
        end

        M.attach(target_server, cb, clear_last)
    end)
end

---@param target_server mux.Server
---@param cb? fun(ok?: true, err?: string)
---@param clear_last? boolean
---@return nil
function M.switch(target_server, cb, clear_last)
    if
        not ours(target_server.socket)
        or socket_listening(target_server.socket)
    then
        M.attach(target_server, cb, clear_last)
        return
    end

    M.connect(target_server.root, cb, clear_last)
end

---Match a server's colorscheme to this one's.
---@param socket string
---@return nil
function M.theme(socket)
    local name = vim.g.colors_name

    if not name then
        return
    end

    spawn_nvim({
        '--server',
        socket,
        '--remote-expr',
        SET_THEME_EXPR:format(vim.fn.string(name)),
    }, { text = true })
end

---Name a server the way the tabline shows it.
---@param server mux.Server
---@return string
function M.label(server)
    local name = vim.fn.fnamemodify(server.root, ':t')

    return server.host and ('%s:%s'):format(server.host, name) or name
end

---@param server mux.Server
---@return nil
local function hand_off(server)
    local attached = #vim.api.nvim_list_uis() > 0
    local peer = peer_for(server.root)
    local address = peer and peer.socket
    local name = peer and M.label(peer) or server.root

    if attached and not address then
        vim.notify(
            ('mux: cannot restart %s: no address to hand its UI'):format(name),
            vim.log.levels.ERROR
        )
        return
    end

    vim.fn.serverstop(server.socket)
    local proc, spawn_err = spawn_nvim({
        '--headless',
        '--listen',
        server.socket,
        ('+lua require("mux.server").setup(%q)'):format(server.root),
    }, {
        cwd = server.root,
        detach = true,
        stdout = false,
        stderr = false,
    })

    if
        not proc
        or not vim.wait(READY_TIMEOUT_MS, function()
            return socket_listening(server.socket)
        end, READY_POLL_MS)
    then
        if proc then
            pcall(proc.kill, proc, 15)
        end

        pcall(vim.fn.serverstart, server.socket)
        vim.notify(
            ('mux: cannot restart %s: %s'):format(
                name,
                spawn_err or 'replacement never answered'
            ),
            vim.log.levels.ERROR
        )
        return
    end

    local carry = {}

    if vim.g.mux_peers then
        carry[#carry + 1] =
            SET_PEERS_EXPR:format(vim.fn.string(vim.g.mux_peers))
    end

    if vim.g.mux_last_root then
        carry[#carry + 1] =
            SET_LAST_ROOT_EXPR:format(vim.fn.string(vim.g.mux_last_root))
    end

    if attached then
        carry[#carry + 1] = RESTARTED_EXPR:format(
            vim.fn.string(('mux: %s restarted'):format(name))
        )
    end

    for _, expr in ipairs(carry) do
        local handoff = spawn_nvim({
            '--server',
            server.socket,
            '--remote-expr',
            expr,
        }, { text = true })
        if handoff then
            handoff:wait(READY_TIMEOUT_MS)
        end
    end

    if attached then
        local ok, connect_err =
            pcall(vim.cmd.connect, vim.fn.fnameescape(address))
        if not ok then
            pcall(proc.kill, proc, 15)
            pcall(vim.fn.serverstart, server.socket)
            vim.notify(
                ('mux: cannot restart %s: %s'):format(
                    name,
                    tostring(connect_err)
                ),
                vim.log.levels.ERROR
            )
            return
        end
    end

    vim.cmd.qall({ bang = true })
end

---Save the user session before restarting this mux server.
---@return true? ok
---@return string? err
function M.reload()
    local server = current_server
    if not server then
        return nil, setup_error or 'not a mux server'
    end

    local session = require('mux.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end

    vim.schedule(function()
        hand_off(server)
    end)

    return true
end

---Initialize this process as the mux server for `root`.
---The root is baked into the respawn, so it outlives any `:cd` the session makes.
---@param root string
---@return true? ok
---@return string? err
function M.setup(root)
    if setup_started then
        return true
    end

    setup_started = true
    local real, err = validate_root(root)

    if not real then
        setup_error = err
        return nil, err
    end

    local server, serr = server_for(real, vim.v.servername)
    if not server then
        setup_error = serr
        return nil, serr
    end

    current_server = server
    require('config.direnv').load(server.root)
    vim.o.sessionoptions =
        'buffers,curdir,folds,globals,help,tabpages,winsize,winpos'
    require('mux.session').setup()
    require('mux.view').setup()
    require('mux.line').setup()

    vim.api.nvim_create_autocmd('UIEnter', {
        group = vim.api.nvim_create_augroup('mux-ui', { clear = true }),
        callback = function()
            vim.cmd('silent! %detach')
        end,
    })

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

M.socket_listening = socket_listening
M.within_sun_path = within_sun_path

M._validate_root = validate_root
M._paths_for = paths_for

return M
