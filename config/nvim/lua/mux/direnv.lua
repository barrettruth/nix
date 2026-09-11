local M = {}

local loading = {}

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

local function warn(result)
    local detail = vim.trim(result.stderr):match('[^\n]+')
    vim.notify(
        'direnv: ' .. (detail or ('failed with exit %d'):format(result.code)),
        vim.log.levels.WARN
    )
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

    if changed then
        vim.notify(
            'direnv: environment changed; restart to update running jobs',
            vim.log.levels.INFO
        )
    end
end

local function progress_buffer(key)
    return vim.iter(vim.api.nvim_list_bufs()):find(function(buf)
        return vim.b[buf].mux_direnv == key
    end)
end

local function close_progress(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
    end
end

local function new_progress(key)
    close_progress(progress_buffer(key))
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'direnv://' .. key)
    vim.b[buf].mux_direnv = key
    vim.b[buf].term_normal = true
    vim.bo[buf].bufhidden = 'wipe'
    vim.keymap.set('n', 'q', function()
        close_progress(buf)
    end, { buffer = buf })
    return buf
end

local function show_progress(buf, target)
    local current = vim.api.nvim_get_current_win()
    local mode = vim.api.nvim_get_mode().mode
    target = target or current
    if vim.api.nvim_win_get_config(target).relative ~= '' then
        target = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
            return vim.api.nvim_win_get_config(win).relative == ''
        end)
    end
    local height = math.max(
        3,
        math.min(12, math.floor(vim.api.nvim_win_get_height(target) * 0.3))
    )
    local win
    vim.api.nvim_win_call(target, function()
        vim.cmd(('belowright %dsplit'):format(height))
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
        vim.wo[win].cursorline = false
    end)
    if vim.api.nvim_win_is_valid(current) then
        vim.api.nvim_set_current_win(current)
        if mode:sub(1, 1) == 't' then
            vim.cmd.startinsert()
        end
    end
    return win
end

local function export(target, callback)
    local result = { stdout = '' }
    local stderr = {}
    local buf, job, channel, timer
    local delay = (tonumber(vim.env.DIRENV_INSTANT_MUX_DELAY) or 4) * 1000

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
        buf = new_progress(target)
        show_progress(buf)
        channel = vim.api.nvim_open_term(buf, {
            on_input = function(_, _, _, data)
                if data:find('\003', 1, true) then
                    vim.schedule(function()
                        close_progress(buf)
                    end)
                end
            end,
        })
        vim.api.nvim_create_autocmd('BufWipeout', {
            buffer = buf,
            once = true,
            callback = function()
                vim.fn.jobstop(job)
            end,
        })
        vim.api.nvim_chan_send(channel, table.concat(stderr))
    end

    timer = vim.defer_fn(show, delay)
    local function complete(_, code)
        result.code = code
        if not timer:is_closing() then
            timer:stop()
            timer:close()
        end
        if vim.v.exiting ~= vim.NIL then
            callback()
            return
        end
        if target ~= root() or (buf and not vim.api.nvim_buf_is_valid(buf)) then
            close_progress(buf)
            callback()
        elseif code == 0 then
            if buf or result.stdout ~= '' then
                close_progress(progress_buffer(target))
            end
            callback(result)
        else
            if #stderr == 0 then
                stderr[1] = ('direnv: export failed with exit %d\n'):format(
                    code
                )
            end
            show()
            vim.api.nvim_chan_send(
                channel,
                ('\r\n[Process exited %d]\r\n'):format(code)
            )
            vim.fn.chanclose(channel)
            callback(result)
        end
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
    local function finish(output)
        local pending = loading[target] == 'pending'
        release()
        if not current() then
            return
        end
        if output then
            apply(output)
        end
        if pending then
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
                    warn(result)
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
                finish(result.stdout)
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

function M.watch(params)
    if
        type(params) ~= 'table'
        or type(params.log) ~= 'string'
        or type(params.socket) ~= 'string'
        or not tonumber(params.shell_pid)
    then
        return false
    end

    vim.schedule(function()
        if progress_buffer(params.socket) then
            return
        end

        local target = terminal_window(tonumber(params.shell_pid))
        if not target then
            return
        end

        local buf = new_progress(params.socket)
        local win = show_progress(buf, target)
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
                        close_progress(buf)
                    end),
                }
            )
            if job <= 0 then
                close_progress(buf)
            end
        end)
    end)

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
