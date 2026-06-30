local M = {}

M.root = vim.fs.normalize('~/dev/cp')
M.root_pattern = '^' .. vim.pesc(M.root) .. '/'

local modes = { run = true, debug = true }

---@param msg string
---@param level? integer
local function notify(msg, level)
    vim.notify('[cp]: ' .. msg, level or vim.log.levels.INFO)
end

---@param path string?
---@return boolean
function M.is_cp_path(path)
    return path ~= nil and path ~= '' and vim.fs.relpath(M.root, path) ~= nil
end

---@param chan integer
---@param data string
local function term_send(chan, data)
    if data == '' then
        return
    end
    data = data:gsub('\n', '\r\n')
    vim.schedule(function()
        pcall(vim.api.nvim_chan_send, chan, data)
    end)
end

---@param chan integer
---@return fun(_: integer, data: string[])
local function output_handler(chan)
    return function(_, data)
        term_send(chan, table.concat(data or {}, '\n'))
    end
end

---@param source string
---@return integer?
local function output_win(source)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.b[buf].cp_source == source then
            return win
        end
    end
end

---@param mode 'run'|'debug'
---@param source string
---@param dir string
local function run_terminal(mode, source, dir)
    local source_win = vim.api.nvim_get_current_win()
    local source_view = vim.fn.winsaveview()
    local win = output_win(source)

    if win then
        vim.api.nvim_set_current_win(win)
    else
        vim.cmd('rightbelow vsplit')
    end

    local old_buf = vim.api.nvim_get_current_buf()

    vim.cmd.enew()
    local buf = vim.api.nvim_get_current_buf()
    vim.b[buf].cp_source = source
    vim.b[buf].term_normal = true
    vim.b[buf].term_insert = false

    local chan = vim.api.nvim_open_term(buf, {})

    if vim.b[old_buf].cp_source == source then
        pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
    end

    if vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_set_current_win(source_win)
        vim.fn.winrestview(source_view)
    end

    local file = vim.fn.fnamemodify(source, ':t')
    local cmd = { 'just', mode, file }
    local action = mode == 'debug' and 'debugging' or 'compiling'
    notify(action .. '...')
    vim.fn.jobstart(cmd, {
        cwd = dir,
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = output_handler(chan),
        on_stderr = output_handler(chan),
        on_exit = function(_, code)
            vim.schedule(function()
                notify(
                    'exited with code ' .. code,
                    code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
                )
            end)
        end,
    })
end

---@param mode? 'run'|'debug'
function M.run(mode)
    mode = mode or 'run'
    if not modes[mode] then
        notify('unknown mode: ' .. mode, vim.log.levels.ERROR)
        return
    end

    local source = vim.api.nvim_buf_get_name(0)
    if not M.is_cp_path(source) then
        notify('not in ~/dev/cp', vim.log.levels.ERROR)
        return
    end
    if vim.bo.filetype ~= 'cpp' then
        notify('only C++ files are supported', vim.log.levels.ERROR)
        return
    end
    if vim.bo.modified then
        vim.cmd.write()
    end

    run_terminal(mode, source, vim.fn.fnamemodify(source, ':h'))
end

function M.setup()
    vim.api.nvim_create_user_command('CP', function(opts)
        M.run(opts.args ~= '' and opts.args or 'run')
    end, {
        nargs = '?',
        complete = function()
            return { 'run', 'debug' }
        end,
    })
    vim.keymap.set('n', '<leader>c', function()
        M.run('run')
    end, { desc = 'run CP problem' })
end

return M
