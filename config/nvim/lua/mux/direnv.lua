local core = require('mux.core')

local M = {}

---@param target_pid integer
---@return integer?
local function find_terminal_win(target_pid)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.api.nvim_buf_is_valid(buf)
            and vim.bo[buf].buftype == 'terminal'
            and tonumber(vim.b[buf].terminal_job_pid) == target_pid
        then
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

---@param socket string
---@return boolean
local function watcher_exists(socket)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.api.nvim_buf_is_valid(buf)
            and vim.b[buf].mux_direnv_watch
            and vim.b[buf].mux_direnv_socket == socket
            and #vim.fn.win_findbuf(buf) > 0
        then
            return true
        end
    end
    return false
end

---@param params { bin?: string, log: string, socket: string, shell_pid: integer|string }
---@return boolean
function M.watch(params)
    if type(params) ~= 'table' then
        return false
    end
    local log = params.log
    local socket = params.socket
    local shell_pid = tonumber(params.shell_pid)
    if type(log) ~= 'string' or type(socket) ~= 'string' or not shell_pid then
        return false
    end
    local bin = type(params.bin) == 'string' and params.bin ~= '' and params.bin
        or 'direnv-instant'

    vim.schedule(function()
        if watcher_exists(socket) then
            return
        end
        local target_win = find_terminal_win(shell_pid)
        if not target_win then
            return
        end
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
            else
                pcall(vim.api.nvim_win_close, watcher_win, true)
            end
        end)
        if vim.api.nvim_tabpage_is_valid(saved_tab) then
            pcall(vim.api.nvim_set_current_tabpage, saved_tab)
        end
        if vim.api.nvim_win_is_valid(saved_win) then
            pcall(vim.api.nvim_set_current_win, saved_win)
        end
        core.restore_terminal_focus()
    end)
    return true
end

return M
