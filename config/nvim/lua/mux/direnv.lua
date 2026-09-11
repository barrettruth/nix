local M = {}

local loading = {}
local watching = {}

local function root()
    local server = require('mux.server').state().server
    local target = (server and server.root) or vim.fn.getcwd(-1, -1, -1)

    return vim.uv.fs_realpath(target) or vim.fs.normalize(target)
end

---@param args string[]
---@return string[] command
function M.unload(args)
    local direnv = vim.fn.exepath('direnv')
    if direnv == '' then
        return args
    end

    local command = { direnv, 'exec', '/' }
    vim.list_extend(command, args)

    return command
end

local function progress(target)
    local label = vim.fs.basename(target) or target
    local state = { kind = 'progress', source = 'direnv', title = label }
    local verbs = {
        running = 'loading',
        success = 'loaded',
        failed = 'failed',
        cancel = 'cancelled',
    }
    return function(status, changed, quiet, detail)
        if state.status and state.status ~= 'running' then
            return
        end
        if status == 'running' and state.id then
            return
        end
        state.status = status
        if
            not state.id
            and (quiet or (status ~= 'running' and status ~= 'failed'))
        then
            return
        end
        local message = 'direnv: ' .. verbs[status] .. ' ' .. label
        if changed and status == 'success' then
            message = message .. '; restart running jobs to use changes'
        end
        if detail then
            message = message .. ': ' .. detail
        end
        state.id = vim.api.nvim_echo(
            quiet and {} or { { message } },
            status == 'failed' and not quiet,
            state
        )
    end
end

local function apply(output)
    output = vim.trim(output)
    if output == '' then
        return
    end

    local exported = vim.json.decode(output)

    local changed = false
    for key, value in pairs(exported) do
        local next_value = value ~= vim.NIL and value or nil
        if
            vim.env[key] ~= next_value and not vim.startswith(key, 'DIRENV_')
        then
            changed = true
        end
        vim.env[key] = next_value
    end

    return changed
end

local function progress_buffer(key)
    return vim.iter(vim.api.nvim_list_bufs()):find(function(buf)
        return vim.b[buf].mux_direnv == key
    end)
end

local function close_progress(buf)
    require('mux.view').close_buffer(buf)
end

local function new_progress(key, on_close)
    local view = require('mux.view')
    local previous = progress_buffer(key)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].mux_direnv = key
    vim.b[buf].term_normal = true
    vim.bo[buf].bufhidden = 'wipe'
    vim.keymap.set('n', 'q', on_close or function()
        close_progress(buf)
    end, { buffer = buf })

    local win = assert(view.mount('direnv', buf, previous))
    vim.wo[win].cursorline = false
    vim.api.nvim_buf_set_name(buf, 'direnv://' .. key)
    return buf, win
end

local function warn(target, result)
    local message = vim.trim(result.stderr or '')
    if message == '' then
        message = ('failed with exit %d'):format(result.code)
    end
    local buf = new_progress(target)
    local channel = vim.api.nvim_open_term(buf, {})
    vim.api.nvim_chan_send(channel, message .. '\r\n')
    vim.fn.chanclose(channel)
    progress(target)('failed', nil, nil, message:match('[^\n]+'))
end

local function export(target, callback)
    local result = { stdout = '' }
    local stderr = {}
    local buf, job, channel, timer
    local previous = progress_buffer(target)
    local report = progress(target)
    local delay = (tonumber(vim.env.DIRENV_INSTANT_MUX_DELAY) or 4) * 1000

    local function cancel()
        if result.code == nil then
            result.cancelled = true
        end
        close_progress(buf)
    end

    local function show()
        if
            vim.v.exiting ~= vim.NIL
            or buf
            or target ~= root()
            or #stderr == 0
            or result.code == 0
        then
            return
        end
        if result.code == nil and not timer:is_closing() then
            return
        end
        buf = new_progress(target, cancel)
        channel = vim.api.nvim_open_term(buf, {
            on_input = function(_, _, _, data)
                if data:find('\003', 1, true) then
                    vim.schedule(cancel)
                end
            end,
        })
        vim.api.nvim_create_autocmd('BufWipeout', {
            buffer = buf,
            once = true,
            callback = function()
                if result.code == nil then
                    vim.fn.jobstop(job)
                end
            end,
        })
        vim.api.nvim_chan_send(channel, table.concat(stderr))
        if result.code == nil then
            report('running')
        end
    end

    timer = vim.defer_fn(show, delay)
    local function complete(_, code)
        result.code = code
        if not timer:is_closing() then
            timer:stop()
            timer:close()
        end
        if vim.v.exiting ~= vim.NIL then
            report('cancel', nil, true)
            callback()
            return
        end
        if target ~= root() or (buf and not vim.api.nvim_buf_is_valid(buf)) then
            report('cancel', nil, not result.cancelled)
            close_progress(buf)
            callback()
            return
        end
        local applied, changed = pcall(apply, result.stdout)
        if not applied then
            result.code = 1
            local message = 'direnv: could not apply exported environment\n'
            stderr[#stderr + 1] = message
            if channel then
                vim.api.nvim_chan_send(channel, message)
            end
        end
        if result.code == 0 then
            report('success', changed)
            close_progress(buf or previous)
        else
            if #stderr == 0 then
                stderr[1] = ('direnv: export failed with exit %d\n'):format(
                    result.code
                )
            end
            show()
            vim.api.nvim_chan_send(
                channel,
                ('\r\n[Process exited %d]\r\n'):format(result.code)
            )
            vim.fn.chanclose(channel)
            report('failed')
        end
        callback(result)
    end

    job = vim.fn.jobstart({ 'direnv', 'export', 'json' }, {
        cwd = target,
        env = { DIRENV_LOG_FORMAT = 'direnv: %s' },
        stdin = 'null',
        stdout_buffered = true,
        on_stdout = function(_, data)
            result.stdout = table.concat(data, '\n')
        end,
        on_stderr = vim.schedule_wrap(function(_, data)
            local chunk = table.concat(data, '\n')
            if chunk == '' or vim.v.exiting ~= vim.NIL then
                return
            end
            if buf then
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_chan_send(channel, chunk)
                end
            else
                stderr[#stderr + 1] = chunk
                show()
            end
        end),
        on_exit = vim.schedule_wrap(complete),
    })
    if job <= 0 then
        stderr[1] = 'direnv: failed to start export\n'
        complete(job, 1)
    end
end

function M.refresh()
    if vim.v.exiting ~= vim.NIL or vim.fn.executable('direnv') ~= 1 then
        return
    end
    local target = root()
    if loading[target] then
        loading[target] = 'pending'
        return
    end

    loading[target] = 'running'
    local function current()
        return vim.v.exiting == vim.NIL and target == root()
    end
    local function release()
        loading[target] = nil
    end
    local function finish()
        local pending = loading[target] == 'pending'
        release()
        if current() and pending then
            M.refresh()
        end
    end

    local function run(args, callback)
        vim.system(
            vim.list_extend({ 'direnv' }, args),
            {
                cwd = target,
                env = { DIRENV_LOG_FORMAT = '' },
                text = true,
            },
            vim.schedule_wrap(function(result)
                if not current() then
                    release()
                elseif result.code ~= 0 then
                    warn(target, result)
                    finish()
                else
                    callback(result.stdout)
                end
            end)
        )
    end
    local function load()
        export(target, function(result)
            if result then
                finish()
            else
                release()
            end
        end)
    end

    run({ 'status', '--json' }, function(output)
        local rc = vim.json.decode(output).state.foundRC
        if rc == vim.NIL or rc.allowed == 0 then
            load()
            return
        end
        if #vim.api.nvim_list_uis() == 0 then
            release()
            return
        end

        local choice = vim.fn.confirm(
            ('direnv: allow %s?'):format(rc.path),
            '&Yes\n&No',
            2
        )
        if not current() or choice ~= 1 then
            release()
            return
        end
        run({ 'allow', rc.path }, load)
    end)
end

local function terminal_window(shell_pid)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buftype == 'terminal' and not vim.b[buf].mux_direnv then
            local ok, pid = pcall(vim.fn.jobpid, vim.bo[buf].channel)
            if ok and pid == shell_pid then
                for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                    if vim.api.nvim_win_get_config(win).relative == '' then
                        return win
                    end
                end
            end
        end
    end
end

local function valid_watch(params)
    return type(params) == 'table'
        and type(params.log) == 'string'
        and type(params.socket) == 'string'
        and (params.target == nil or type(params.target) == 'string')
        and tonumber(params.shell_pid) ~= nil
end

local function watch_operation(params)
    local previous = watching[params.socket]
    if previous then
        previous.report('cancel', nil, true)
    end
    local operation = {
        log = params.log,
        target = type(params.target) == 'string' and params.target or nil,
        report = progress(params.target or root()),
    }
    watching[params.socket] = operation
    return operation
end

function M.watch(params)
    if not valid_watch(params) then
        return false
    end

    vim.schedule(function()
        local existing = watching[params.socket]
        if existing and existing.log == params.log then
            return
        end
        if
            not vim.uv.fs_stat(params.log)
            or not terminal_window(tonumber(params.shell_pid))
        then
            return
        end

        local operation = watch_operation(params)
        local buf, win = new_progress(params.socket)
        operation.buf = buf
        local bin = type(params.bin) == 'string'
                and params.bin ~= ''
                and params.bin
            or 'direnv-instant'
        vim.api.nvim_win_call(win, function()
            local job = vim.fn.jobstart(
                { bin, 'watch', params.log, params.socket },
                {
                    term = true,
                    cwd = root(),
                    on_exit = vim.schedule_wrap(function()
                        if
                            watching[params.socket] ~= operation
                            or operation.result
                        then
                            return
                        end
                        if not operation.target then
                            close_progress(buf)
                            watching[params.socket] = nil
                        elseif vim.api.nvim_buf_is_valid(buf) then
                            vim.b[buf].terminal_job_id = nil
                        end
                    end),
                }
            )
            if job <= 0 then
                local channel = vim.api.nvim_open_term(buf, {})
                vim.api.nvim_chan_send(
                    channel,
                    'direnv: failed to start output reader\r\n'
                )
                vim.fn.chanclose(channel)
            end
            if operation.target then
                operation.report('running')
            end
        end)
    end)

    return true
end

function M.finish_watch(params)
    if
        not valid_watch(params)
        or type(params.target) ~= 'string'
        or not vim.tbl_contains(
            { 'success', 'failed', 'cancel' },
            params.status
        )
        or not tonumber(params.code)
    then
        return false
    end
    local operation = watching[params.socket]
    if operation and operation.log == params.log and operation.result then
        return true
    end
    if not operation or operation.log ~= params.log then
        if
            not vim.uv.fs_stat(params.log)
            or not terminal_window(tonumber(params.shell_pid))
            or (
                operation
                and not operation.result
                and vim.uv.fs_stat(operation.log)
            )
        then
            return false
        end
        operation = watch_operation(params)
    end
    operation.result = params.status
    if vim.v.exiting ~= vim.NIL then
        operation.report('cancel', nil, true)
        return true
    end
    if params.status == 'failed' then
        local read, lines = pcall(vim.fn.readfile, params.log, 'b')
        if
            read
            or not (operation.buf and vim.api.nvim_buf_is_valid(operation.buf))
        then
            local output = read and table.concat(lines, '\n')
                or 'direnv: diagnostic output is no longer available\n'
            local buf = new_progress(params.socket)
            operation.buf = buf
            local channel = vim.api.nvim_open_term(buf, {})
            vim.api.nvim_chan_send(
                channel,
                output .. ('\r\n[Process exited %d]\r\n'):format(params.code)
            )
            vim.fn.chanclose(channel)
        end
    else
        close_progress(operation.buf or progress_buffer(params.socket))
    end
    operation.report(params.status)
    return true
end

function M.setup()
    local group = vim.api.nvim_create_augroup('Direnv', { clear = true })
    vim.api.nvim_create_autocmd(
        { 'BufWritePost', 'DirChanged', 'FocusGained', 'UIEnter' },
        {
            group = group,
            callback = function()
                M.refresh()
            end,
        }
    )
    M.refresh()
end

return M
