local core = require('mux.core')

---@class mux.direnv.WatchParams
---@field bin? string
---@field log string
---@field socket string
---@field shell_pid integer|string

---@class mux.direnv
---@field watch fun(params: mux.direnv.WatchParams): boolean
local M = {}

---@type table<string, true>
local pending = {}

---@param target_pid integer
---@return integer?
local function find_terminal_win(target_pid)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.api.nvim_buf_is_valid(buf)
            and vim.bo[buf].buftype == 'terminal'
        then
            local ok, job_pid =
                pcall(vim.api.nvim_buf_get_var, buf, 'terminal_job_pid')
            if ok and tonumber(job_pid) == target_pid then
                for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                    if
                        vim.api.nvim_win_is_valid(win)
                        and vim.api.nvim_win_get_config(win).relative == ''
                    then
                        return win
                    end
                end
            end
        end
    end
end

---@param socket string
---@return boolean
local function watcher_exists(socket)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            local watch_ok, watch =
                pcall(vim.api.nvim_buf_get_var, buf, 'mux_direnv_watch')
            local socket_ok, watch_socket =
                pcall(vim.api.nvim_buf_get_var, buf, 'mux_direnv_socket')
            if
                watch_ok
                and watch
                and socket_ok
                and watch_socket == socket
                and vim.fn.bufwinid(buf) ~= -1
            then
                return true
            end
        end
    end
    return false
end

---@param params mux.direnv.WatchParams
---@return boolean
function M.watch(params)
    if type(params) ~= 'table' then
        core.log('direnv-watch: rejected non-table params')
        return false
    end
    local log = params.log
    local socket = params.socket
    local shell_pid = tonumber(params.shell_pid)
    if type(log) ~= 'string' or type(socket) ~= 'string' or not shell_pid then
        core.log('direnv-watch: rejected invalid params')
        return false
    end
    local bin = type(params.bin) == 'string' and params.bin ~= '' and params.bin
        or 'direnv-instant'
    core.log(
        ('direnv-watch: requested shell_pid=%s socket=%s log=%s'):format(
            shell_pid,
            socket,
            log
        )
    )

    vim.schedule(function()
        if pending[socket] then
            core.log('direnv-watch: skipped pending socket=' .. socket)
            return
        end
        if watcher_exists(socket) then
            core.log('direnv-watch: skipped existing socket=' .. socket)
            return
        end
        pending[socket] = true
        local target_win = find_terminal_win(shell_pid)
        if target_win then
            local saved_win = vim.api.nvim_get_current_win()
            local saved_tab = vim.api.nvim_get_current_tabpage()
            vim.api.nvim_win_call(target_win, function()
                vim.cmd('belowright 10split')
                vim.cmd.enew()
                local watcher_win = vim.api.nvim_get_current_win()
                vim.wo[watcher_win].cursorline = false
                local job = vim.fn.jobstart(
                    { bin, 'watch', log, socket },
                    { term = true, cwd = vim.fn.getcwd() }
                )
                if job > 0 then
                    local watcher_buf = vim.api.nvim_win_get_buf(watcher_win)
                    vim.b[watcher_buf].mux_direnv_watch = true
                    vim.b[watcher_buf].mux_direnv_socket = socket
                    vim.bo[watcher_buf].buflisted = false
                    core.log(
                        ('direnv-watch: opened job=%s buf=%s'):format(
                            job,
                            watcher_buf
                        )
                    )
                else
                    core.log('direnv-watch: jobstart failed')
                    pcall(vim.api.nvim_win_close, watcher_win, true)
                end
            end)
            if vim.api.nvim_tabpage_is_valid(saved_tab) then
                pcall(vim.api.nvim_set_current_tabpage, saved_tab)
            end
            if vim.api.nvim_win_is_valid(saved_win) then
                pcall(vim.api.nvim_set_current_win, saved_win)
                core.restore_terminal_focus()
            end
        else
            core.log('direnv-watch: target window not found')
        end
        pending[socket] = nil
    end)
    return true
end

return M
