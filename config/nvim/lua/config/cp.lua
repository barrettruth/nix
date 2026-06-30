local M = {}

M.root = vim.fs.normalize('~/dev/cp')
M.root_pattern = '^' .. vim.pesc(M.root) .. '/'
M.template = vim.fs.joinpath(M.root, 'template.cc')

local modes = { run = true, debug = true }
local active = {}

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

local function close_output()
    local job = active.job
    active.job = nil
    if job and job > 0 then
        pcall(vim.fn.jobstop, job)
    end

    local buf = active.output_buf
    active.output_buf = nil
    active.source_buf = nil
    if buf and vim.api.nvim_buf_is_valid(buf) then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
            pcall(vim.api.nvim_win_close, win, true)
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
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
        local lines = {}
        for _, line in ipairs(data or {}) do
            if
                not line:match(
                    '^error: recipe .- failed on line %d+ with exit code %d+$'
                )
            then
                lines[#lines + 1] = line
            end
        end
        term_send(chan, table.concat(lines, '\n'))
    end
end

---@param mode 'run'|'debug'
---@param source_buf integer
---@param source string
---@param dir string
local function run_terminal(mode, source_buf, source, dir)
    local source_win = vim.api.nvim_get_current_win()
    local source_view = vim.fn.winsaveview()

    close_output()
    vim.cmd('rightbelow vsplit')
    vim.cmd.enew()

    local buf = vim.api.nvim_get_current_buf()
    active.source_buf = source_buf
    active.output_buf = buf
    vim.b[buf].cp_source = source
    vim.b[buf].term_normal = true
    vim.b[buf].term_insert = false
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].buflisted = false
    vim.bo[buf].swapfile = false

    local chan = vim.api.nvim_open_term(buf, {})
    vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        once = true,
        callback = function()
            if active.output_buf == buf then
                active.output_buf = nil
                active.source_buf = nil
                if active.job then
                    pcall(vim.fn.jobstop, active.job)
                    active.job = nil
                end
            end
        end,
    })

    if vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_set_current_win(source_win)
        vim.fn.winrestview(source_view)
    end

    local file = vim.fn.fnamemodify(source, ':t')
    local cmd = { 'just', mode, file }
    local action = mode == 'debug' and 'debugging' or 'compiling'
    notify(action .. '...')
    local job = vim.fn.jobstart(cmd, {
        cwd = dir,
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = output_handler(chan),
        on_stderr = output_handler(chan),
        on_exit = function(_, code)
            vim.schedule(function()
                if active.job == job then
                    active.job = nil
                    notify(
                        'exited with code ' .. code,
                        code == 0 and vim.log.levels.INFO
                            or vim.log.levels.ERROR
                    )
                end
            end)
        end,
    })
    if job > 0 then
        active.job = job
    end
end

local function close_if_source_hidden()
    vim.schedule(function()
        if
            active.source_buf
            and active.output_buf
            and (
                not vim.api.nvim_buf_is_valid(active.source_buf)
                or #vim.fn.win_findbuf(active.source_buf) == 0
            )
        then
            close_output()
        end
    end)
end

---@return boolean
local function populate_template_if_empty()
    if
        vim.api.nvim_buf_line_count(0) ~= 1
        or vim.api.nvim_get_current_line() ~= ''
    then
        return false
    end

    local ok, lines = pcall(vim.fn.readfile, M.template)
    if not ok then
        notify('failed to read template', vim.log.levels.ERROR)
        return false
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    return true
end

local function go_to_solve()
    local line
    for lnum, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if text:match('^%s*void%s+solve%(%).*{%s*$') then
            line = lnum
            break
        end
    end
    if not line then
        return
    end

    local target = math.min(line + 1, vim.api.nvim_buf_line_count(0))
    local text = vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1]
    vim.api.nvim_win_set_cursor(0, { target, #(text or '') })
    vim.cmd.normal({ 'zv', bang = true })
end

---@param problem string
function M.open_problem(problem)
    local cwd = vim.fn.getcwd()
    if not M.is_cp_path(cwd) then
        notify('not in ~/dev/cp', vim.log.levels.ERROR)
        return
    end

    close_output()
    problem = problem:gsub('%.cc$', '') .. '.cc'
    vim.cmd.edit(vim.fn.fnameescape(problem))
    if populate_template_if_empty() then
        vim.cmd.write()
        vim.cmd.edit()
    end
    go_to_solve()
end

---@param mode? 'run'|'debug'
function M.run(mode)
    mode = mode or 'run'
    if not modes[mode] then
        notify('unknown mode: ' .. mode, vim.log.levels.ERROR)
        return
    end

    local source_buf = vim.api.nvim_get_current_buf()
    local source = vim.api.nvim_buf_get_name(source_buf)
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

    run_terminal(mode, source_buf, source, vim.fn.fnamemodify(source, ':h'))
end

function M.setup()
    local group = vim.api.nvim_create_augroup('Cp', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufWinLeave', 'BufWipeout', 'WinClosed' }, {
        group = group,
        callback = close_if_source_hidden,
    })

    vim.api.nvim_create_user_command('CP', function(opts)
        local arg = opts.args
        if arg == '' or modes[arg] then
            M.run(arg ~= '' and arg or 'run')
        else
            M.open_problem(arg)
        end
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
