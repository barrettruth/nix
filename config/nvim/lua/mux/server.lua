---@class mux.Server
---@field root string
---@field session string
---@field socket string

---@class mux.State
---@field server? mux.Server
---@field runtime_dir string
---@field state_dir string

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

---@return string
local function runtime_dir()
    local base = vim.env.XDG_RUNTIME_DIR
    if not base or base == '' then
        base = '/run/user/' .. vim.uv.getuid()
    end
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

---Return this server only after setup has completed.
---@return mux.Server? server
---@return string? err
function M.this()
    if not setup_started then
        return nil, 'not a mux server'
    end
    if not ready then
        return nil, setup_error or 'not ready'
    end
    return current_server
end

---Serialize this server's readiness for remote probes.
---@return string
function M.rpc_this()
    local server, err = M.this()
    if not server then
        return vim.json.encode({ ok = false, error = err })
    end
    return vim.json.encode({ ok = true, server = server })
end

local RPC_EXPR = "luaeval('require([[mux.server]]).rpc_this()')"

---@param args string[]
---@param opts table
---@param cb? function
---@return any? proc
---@return string? err
local function spawn_nvim(args, opts, cb)
    local prog = vim.fn.executable(vim.v.progpath) == 1 and vim.v.progpath
        or 'nvim'
    local argv = vim.list_extend({ prog }, args)
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

---@param socket string
---@param timeout? integer
---@return mux.Server? server
---@return string? err
local function rpc_this_sync(socket, timeout)
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
local function rpc_this_async(socket, timeout, cb)
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

---List mux servers that answer readiness probes.
---@return mux.Server[]
function M.list()
    local out = {}
    local sockets = vim.fn.glob(runtime_dir() .. '/*.sock', true, true)
    table.sort(sockets)
    for _, socket in ipairs(sockets) do
        if current_server and socket == current_server.socket then
            out[#out + 1] = current_server
        else
            local server = rpc_this_sync(socket, LIST_PROBE_MS)
            if server and server.socket then
                out[#out + 1] = server
            end
        end
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
    local existing = rpc_this_sync(paths.socket, LIST_PROBE_MS)
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
        rpc_this_async(paths.socket, LIST_PROBE_MS, function(server, rerr)
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
            local entry2 = pending[real]
            if not entry2 then
                return
            end
            entry2.timer = vim.uv.new_timer()
            entry2.timer:start(READY_POLL_MS, 0, poll)
        end)
    end
    poll()
end

---Save the user session before closing this mux server.
---@return true? ok
---@return string? err
function M.close()
    local session = require('mux.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end
    vim.cmd('qall')
    return true
end

---Forget the saved session before force-closing this mux server.
---@return true? ok
---@return string? err
function M.kill()
    local session = require('mux.session')
    local ok, err = session.delete()
    if not ok then
        return nil, err
    end
    vim.cmd('qall!')
    return true
end

---Save the user session before restarting this mux server.
---@return true? ok
---@return string? err
function M.reload()
    if #vim.api.nvim_list_uis() == 0 then
        return nil, 'no UI attached'
    end
    local session = require('mux.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end
    vim.cmd('restart! +qall!')
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
