local M = {}

local loading = {}

local function root()
    local server = require('mux.server').state().server
    local target = (server and server.root) or vim.fn.getcwd(-1, -1, -1)

    return vim.uv.fs_realpath(target) or vim.fs.normalize(target)
end

---@param args string[]
---@return string[]? command
---@return string? err
function M.unload(args)
    local direnv = vim.fn.exepath('direnv')
    if direnv == '' then
        return args
    end

    local command = { direnv, 'exec', '/' }
    vim.list_extend(command, args)

    return command
end

local function apply(result)
    if result.code ~= 0 then
        local detail = vim.trim(result.stderr or ''):match('[^\n]+')
        vim.notify(
            'direnv: '
                .. (detail or ('failed with exit %d'):format(result.code)),
            vim.log.levels.WARN
        )
        return
    end

    local output = vim.trim(result.stdout or '')
    if output == '' then
        return
    end

    local ok, exported = pcall(vim.json.decode, output)
    if not ok or type(exported) ~= 'table' then
        vim.notify('direnv: invalid export', vim.log.levels.WARN)
        return
    end

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

function M.refresh()
    local target = root()
    if loading[target] then
        loading[target] = 'pending'
        return
    end
    if vim.fn.executable('direnv') ~= 1 then
        return
    end

    loading[target] = 'running'
    vim.system({ 'direnv', 'export', 'json' }, {
        cwd = target,
        env = { DIRENV_LOG_FORMAT = '' },
        text = true,
    }, function(result)
        vim.schedule(function()
            local pending = loading[target] == 'pending'
            loading[target] = nil
            if target ~= root() then
                return
            end
            if pending then
                M.refresh()
                return
            end
            apply(result)
        end)
    end)
end

local function terminal_window(shell_pid)
    local fallback
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.bo[buf].buftype == 'terminal'
            and not vim.b[buf].mux_direnv_socket
        then
            local ok, pid = pcall(vim.fn.jobpid, vim.bo[buf].channel)
            for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                if
                    vim.api.nvim_win_is_valid(win)
                    and vim.api.nvim_win_get_config(win).relative == ''
                then
                    if ok and pid == shell_pid then
                        return win
                    end
                    fallback = fallback or win
                end
            end
        end
    end

    return fallback
end

local function watcher_exists(socket)
    return vim.iter(vim.api.nvim_list_bufs()):any(function(buf)
        return vim.b[buf].mux_direnv_socket == socket
            and #vim.fn.win_findbuf(buf) > 0
    end)
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
        if watcher_exists(params.socket) then
            return
        end

        local target = terminal_window(tonumber(params.shell_pid))
        if not target then
            return
        end

        local current = vim.api.nvim_get_current_win()
        local mode = vim.api.nvim_get_mode().mode
        local height = math.max(
            3,
            math.min(12, math.floor(vim.api.nvim_win_get_height(target) * 0.3))
        )
        vim.api.nvim_win_call(target, function()
            vim.cmd(('belowright %dsplit'):format(height))
            vim.cmd.enew()
            local win = vim.api.nvim_get_current_win()
            local buf = vim.api.nvim_get_current_buf()
            local bin = type(params.bin) == 'string'
                    and params.bin ~= ''
                    and params.bin
                or 'direnv-instant'
            local job = vim.fn.jobstart(
                { bin, 'watch', params.log, params.socket },
                {
                    term = true,
                    cwd = root(),
                    on_exit = vim.schedule_wrap(function()
                        if vim.api.nvim_buf_is_valid(buf) then
                            vim.api.nvim_buf_delete(buf, { force = true })
                        end
                    end),
                }
            )
            if job <= 0 then
                vim.api.nvim_win_close(win, true)
                return
            end

            vim.b[buf].mux_direnv_socket = params.socket
            vim.bo[buf].buflisted = false
            vim.wo[win].cursorline = false
        end)

        if vim.api.nvim_win_is_valid(current) then
            vim.api.nvim_set_current_win(current)
            if mode:sub(1, 1) == 't' then
                vim.cmd.startinsert()
            end
        end
    end)

    return true
end

function M.setup()
    local group = vim.api.nvim_create_augroup('Direnv', { clear = true })
    vim.api.nvim_create_autocmd(
        { 'BufWritePost', 'DirChanged', 'FocusGained' },
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
