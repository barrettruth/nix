---@class mx.Server
---@field root string
---@field session string
---@field socket string

---@alias mx.EnsureCallback fun(server?: mx.Server, err?: string)

---@class mx.PendingEnsure
---@field callbacks mx.EnsureCallback[]
---@field timer? any
---@field proc? any

local M = {}

local ready = false
local setup_started = false
local setup_error

---@type mx.Server?
local current_server

---@type table<string, mx.PendingEnsure>
local pending = {}

local READY_TIMEOUT_MS = 5000
local READY_POLL_MS = 50
local LIST_PROBE_MS = 100

local function runtime_dir()
    local base = vim.env.XDG_RUNTIME_DIR
    if not base or base == '' then
        base = '/run/user/' .. vim.uv.getuid()
    end
    return base .. '/mux'
end

local function state_dir()
    return vim.fn.stdpath('state') .. '/mux'
end

local function fs_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function is_dir(path)
    local st = vim.uv.fs_stat(path)
    return st and st.type == 'directory'
end

local function has_marker(root)
    return fs_exists(root .. '/.git') or fs_exists(root .. '/.jj')
end

local function validate_root(root)
    if type(root) ~= 'string' or root == '' then
        return nil, 'empty root'
    end
    local real = vim.uv.fs_realpath(root)
    if not real then
        return nil, 'invalid root: ' .. root
    end
    if not is_dir(real) then
        return nil, 'not a directory: ' .. real
    end
    if not has_marker(real) then
        return nil, 'invalid root: ' .. real
    end
    return real
end

local function sanitize_base(base)
    base = (base or ''):gsub('[^A-Za-z0-9._-]', '_')
    base = base:gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if base == '' then
        return 'project'
    end
    return base
end

local function cksum(s)
    local res = vim.system({ 'cksum' }, { text = true, stdin = s }):wait()
    if not res or res.code ~= 0 or not res.stdout then
        return nil, 'cksum failed'
    end
    return res.stdout:match('^(%d+)')
end

local function stem(root)
    local hash, err = cksum(root)
    if not hash then
        return nil, err
    end
    return sanitize_base(vim.fn.fnamemodify(root, ':t')) .. '-' .. hash
end

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

---@return mx.Server?
function M._record()
    return current_server
end

---@return string
function M.runtime_dir()
    return runtime_dir()
end

---@return string
function M.state_dir()
    return state_dir()
end

---@param root string
---@return mx.Server? paths
---@return string? err
function M.paths(root)
    local real, err = validate_root(root)
    if not real then
        return nil, err
    end
    return paths_for(real)
end

---@return mx.Server? server
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

---@return string
function M.rpc_this()
    local server, err = M.this()
    if not server then
        return vim.json.encode({ ok = false, error = err })
    end
    return vim.json.encode({ ok = true, server = server })
end

local RPC_EXPR = "luaeval('require([[mx.server]]).rpc_this()')"

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

local function rpc_this_sync(socket, timeout)
    local proc = vim.system(
        { vim.v.progpath, '--server', socket, '--remote-expr', RPC_EXPR },
        { text = true, stdout = true, stderr = true }
    )
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

local function rpc_this_async(socket, timeout, cb)
    local done = false
    local timer = vim.uv.new_timer()
    local proc
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
    proc = vim.system(
        { vim.v.progpath, '--server', socket, '--remote-expr', RPC_EXPR },
        { text = true, stdout = true, stderr = true },
        function(res)
            if res.code ~= 0 then
                finish(nil, vim.trim(res.stderr or ''))
                return
            end
            local server, err = decode_rpc(res.stdout)
            finish(server, err)
        end
    )
    timer:start(timeout, 0, function()
        pcall(proc.kill, proc, 15)
        finish(nil, 'timeout')
    end)
end

---@return mx.Server[]
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

local function contains(path, root)
    if path == root then
        return true
    end
    return vim.startswith(path, root .. '/')
end

---@param path string
---@return mx.Server? server
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
                'mx: ensure callback failed: ' .. tostring(cb_err),
                vim.log.levels.ERROR
            )
        end
    end
end

---@param root string
---@param cb mx.EnsureCallback
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
    if fs_exists(paths.socket) then
        pcall(vim.fn.delete, paths.socket)
    end
    pcall(vim.fn.mkdir, runtime_dir(), 'p')
    pcall(vim.fn.mkdir, state_dir(), 'p')
    pending[real] = { callbacks = { cb } }
    local proc = vim.system({
        vim.v.progpath,
        '--headless',
        '--listen',
        paths.socket,
        '+lua require("mx.server").setup()',
    }, {
        cwd = real,
        detach = true,
        stdout = false,
        stderr = false,
    })
    pending[real].proc = proc
    local started = vim.uv.now()
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

---@return true? ok
---@return string? err
function M.detach()
    local session = require('mx.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end
    vim.cmd.detach()
    return true
end

---@return true? ok
---@return string? err
function M.close()
    local session = require('mx.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end
    vim.cmd('qall')
    return true
end

---@return true? ok
---@return string? err
function M.reload()
    if #vim.api.nvim_list_uis() == 0 then
        return nil, 'no UI attached'
    end
    local session = require('mx.session')
    local ok, err = session.save()
    if not ok then
        return nil, err
    end
    vim.cmd('restart! +qall!')
    return true
end

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
    require('mx.session').setup()
    require('mx.view').setup()
    require('mx.line').setup()
    local ok, rerr = require('mx.session').restore()
    if not ok and rerr ~= 'no session' then
        setup_error = rerr
        return nil, rerr
    end
    if not ok then
        require('mx.view').initial()
    end
    ready = true
    require('mx.line').update_servers()
    return true
end

M._validate_root = validate_root
M._paths_for = paths_for
return M
