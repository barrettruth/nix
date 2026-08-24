local M = {}

M.root = vim.fs.normalize('~/dev/cp')
M.root_pattern = '^' .. vim.pesc(M.root) .. '/'

local languages = {
    cpp = { ext = '.cc', solve = '^%s*void%s+solve%(%).*{%s*$' },
    python = { ext = '.py', solve = '^%s*def%s+solve%(%).*:%s*$' },
}

---@class cp.Column
---@field source? integer
---@field output? integer
---@field input? integer
---@field others integer[]

---@param msg string
---@param level? integer
local function notify(msg, level)
    vim.notify('[cp]: ' .. msg, level or vim.log.levels.INFO)
end

---@return { ext: string, solve: string }?
---@return string
local function default_language()
    local name = (vim.g.cp or {}).language or 'python'
    return languages[name], tostring(name)
end

---@param path string?
---@return boolean
function M.is_cp_path(path)
    return path ~= nil and path ~= '' and vim.fs.relpath(M.root, path) ~= nil
end

---@param source string
---@return string
local function input_path(source)
    return vim.fn.fnamemodify(source, ':r') .. '.in'
end

---@param path string
---@return boolean
local function is_input_path(path)
    return M.is_cp_path(path) and path:sub(-3) == '.in'
end

---@param input string
---@return string?
local function source_for_input(input)
    local stem = vim.fn.fnamemodify(input, ':r')
    for _, lang in pairs(languages) do
        if vim.fn.filereadable(stem .. lang.ext) == 1 then
            return stem .. lang.ext
        end
    end
end

---@param source string
---@return string
local function ensure_input(source)
    local path = input_path(source)
    if vim.fn.filereadable(path) == 0 then
        vim.fn.writefile({}, path)
    end
    return path
end

---@param path string
---@return integer?
local function loaded_buf(path)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == path then
            return buf
        end
    end
end

---@param path string
local function write_path(path)
    local buf = loaded_buf(path)
    if buf and vim.bo[buf].modified then
        vim.api.nvim_buf_call(buf, function()
            vim.cmd.write()
        end)
    end
end

---@param a integer
---@param b integer
---@return boolean
local function below_right(a, b)
    local ap = vim.api.nvim_win_get_position(a)
    local bp = vim.api.nvim_win_get_position(b)
    return ap[2] > bp[2] or (ap[2] == bp[2] and ap[1] > bp[1])
end

---@param tp? integer
---@return cp.Column
local function column(tp)
    tp = tp or vim.api.nvim_get_current_tabpage()
    local cur = vim.api.nvim_get_current_win()
    local cols = { others = {} }
    local wins, inputs = {}, {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        if vim.api.nvim_win_get_config(win).relative == '' then
            wins[#wins + 1] = win
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.b[buf].cp_output then
                cols.output = win
            elseif is_input_path(vim.api.nvim_buf_get_name(buf)) then
                inputs[#inputs + 1] = win
            end
        end
    end
    for _, win in ipairs(inputs) do
        if not cols.input or below_right(win, cols.input) then
            cols.input = win
        end
    end
    for _, win in ipairs(wins) do
        if win ~= cols.output and win ~= cols.input then
            cols.others[#cols.others + 1] = win
            local buf = vim.api.nvim_win_get_buf(win)
            if
                languages[vim.bo[buf].filetype]
                and M.is_cp_path(vim.api.nvim_buf_get_name(buf))
                and (not cols.source or win == cur)
            then
                cols.source = win
            end
        end
    end
    return cols
end

---@param buf integer
local function stop_job(buf)
    local job = vim.b[buf].cp_job
    if job then
        vim.b[buf].cp_job = nil
        pcall(vim.fn.jobstop, job)
    end
end

---@param cols cp.Column
local function close_column(cols)
    if cols.output then
        local buf = vim.api.nvim_win_get_buf(cols.output)
        stop_job(buf)
        pcall(vim.api.nvim_win_close, cols.output, true)
        if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
    if cols.input then
        pcall(vim.api.nvim_win_close, cols.input, true)
    end
end

local function close_if_orphaned()
    vim.schedule(function()
        for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
            local cols = column(tp)
            if (cols.output or cols.input) and #cols.others == 0 then
                close_column(cols)
            end
        end
    end)
end

---@param win integer
---@param source string
---@return integer buf
---@return integer chan
local function reset_output(win, source)
    local old = vim.api.nvim_win_get_buf(win)
    if vim.b[old].cp_output then
        stop_job(old)
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].buflisted = false
    vim.bo[buf].swapfile = false
    vim.b[buf].cp_output = true
    vim.b[buf].cp_source = source
    vim.b[buf].term_normal = true
    vim.b[buf].term_insert = false
    vim.api.nvim_win_set_buf(win, buf)
    return buf, vim.api.nvim_open_term(buf, {})
end

---@param output_win integer
---@param input_win integer
local function fix_column(output_win, input_win)
    local total = vim.api.nvim_win_get_height(output_win)
        + vim.api.nvim_win_get_height(input_win)
    vim.api.nvim_win_resize(
        output_win,
        math.max(1, math.floor(vim.o.columns * 0.35)),
        -1
    )
    vim.api.nvim_win_resize(
        input_win,
        -1,
        math.max(1, math.floor(total * 0.35))
    )
    vim.wo[output_win].winfixwidth = true
    vim.wo[input_win].winfixwidth = true
    vim.wo[input_win].winfixheight = true
end

---@param output_win integer
---@param source string
---@return integer input_win
local function attach_input(output_win, source)
    vim.api.nvim_set_current_win(output_win)
    vim.cmd('belowright split ' .. vim.fn.fnameescape(input_path(source)))
    local input_win = vim.api.nvim_get_current_win()
    fix_column(output_win, input_win)
    return input_win
end

---@param input_win integer
---@return integer output_win
local function attach_output(input_win)
    vim.api.nvim_set_current_win(input_win)
    vim.cmd('aboveleft split')
    local output_win = vim.api.nvim_get_current_win()
    fix_column(output_win, input_win)
    return output_win
end

---@param source_win integer
---@param source string
---@return integer output_win
---@return integer input_win
local function open_column(source_win, source)
    vim.api.nvim_set_current_win(source_win)
    vim.cmd('rightbelow vsplit')
    local output_win = vim.api.nvim_get_current_win()
    return output_win, attach_input(output_win, source)
end

---@param win integer
---@param source string
local function retarget_input(win, source)
    local path = input_path(source)
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == path then
        return
    end
    vim.api.nvim_win_call(win, function()
        vim.cmd.edit(vim.fn.fnameescape(path))
    end)
end

---@param source string
---@return integer buf
---@return integer chan
local function ensure_column(source)
    local saved_win = vim.api.nvim_get_current_win()
    local saved_view = vim.fn.winsaveview()
    ensure_input(source)

    local cols = column()
    local output_win, input_win = cols.output, cols.input
    if output_win and not input_win then
        input_win = attach_input(output_win, source)
    elseif input_win and not output_win then
        output_win = attach_output(input_win)
    elseif not output_win then
        output_win, input_win =
            open_column(cols.source or cols.others[1] or saved_win, source)
    end

    local buf, chan = reset_output(output_win, source)
    retarget_input(input_win, source)

    if vim.api.nvim_win_is_valid(saved_win) then
        vim.api.nvim_set_current_win(saved_win)
        vim.fn.winrestview(saved_view)
    end
    return buf, chan
end

---@return string?
local function resolve_source()
    local cols = column()
    if cols.source then
        return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cols.source))
    end
    if cols.output then
        return vim.b[vim.api.nvim_win_get_buf(cols.output)].cp_source
    end
    if cols.input then
        return source_for_input(
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cols.input))
        )
    end
end

local function restore_column()
    local cols = column()
    if cols.output or not cols.input then
        return
    end
    local source = resolve_source()
    if not source then
        return
    end
    local saved_win = vim.api.nvim_get_current_win()
    local saved_view = vim.fn.winsaveview()
    reset_output(attach_output(cols.input), source)
    if vim.api.nvim_win_is_valid(saved_win) then
        vim.api.nvim_set_current_win(saved_win)
        vim.fn.winrestview(saved_view)
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

---@param lang { ext: string, solve: string }
---@return boolean
local function populate_template_if_empty(lang)
    if
        vim.api.nvim_buf_line_count(0) ~= 1
        or vim.api.nvim_get_current_line() ~= ''
    then
        return false
    end

    local template = vim.fs.joinpath(M.root, 'template' .. lang.ext)
    local ok, lines = pcall(vim.fn.readfile, template)
    if not ok then
        notify('failed to read template', vim.log.levels.ERROR)
        return false
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    return true
end

---@param lang { ext: string, solve: string }
local function go_to_solve(lang)
    local line
    for lnum, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if text:match(lang.solve) then
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
---@param lang { ext: string, solve: string }
---@return string?
local function normalize_problem(problem, lang)
    local base = problem:gsub(vim.pesc(lang.ext) .. '$', '')
    if not base:match('^[%w_-]+$') then
        notify('invalid problem name: ' .. problem, vim.log.levels.ERROR)
        return
    end
    return base .. lang.ext
end

local function complete_problem(arg_lead)
    local items = { 'run', 'debug' }
    local lang = default_language()
    if lang then
        for _, file in ipairs(vim.fn.glob('*' .. lang.ext, false, true)) do
            items[#items + 1] = vim.fn.fnamemodify(file, ':r')
        end
    end
    return vim.tbl_filter(function(item)
        return vim.startswith(item, arg_lead)
    end, items)
end

---@param problem string
function M.open_problem(problem)
    local cwd = vim.fn.getcwd()
    if not M.is_cp_path(cwd) then
        notify('not in ~/dev/cp', vim.log.levels.ERROR)
        return
    end

    local lang, name = default_language()
    if not lang then
        notify('unknown language: ' .. name, vim.log.levels.ERROR)
        return
    end

    local file = normalize_problem(problem, lang)
    if not file then
        return
    end

    local cols = column()
    vim.api.nvim_set_current_win(
        cols.source or cols.others[1] or vim.api.nvim_get_current_win()
    )
    if vim.bo.modified then
        vim.cmd.write()
    end

    vim.cmd.edit(vim.fn.fnameescape(file))
    if populate_template_if_empty(lang) then
        vim.cmd.write()
        vim.cmd.edit()
    end
    go_to_solve(lang)
    ensure_column(vim.api.nvim_buf_get_name(0))
end

---@param mode 'run'|'debug'
function M.run(mode)
    local source = resolve_source()
    if not source then
        local name = vim.api.nvim_buf_get_name(0)
        notify(
            M.is_cp_path(name) and ('unsupported filetype: ' .. vim.bo.filetype)
                or 'not in ~/dev/cp',
            vim.log.levels.ERROR
        )
        return
    end

    write_path(source)
    write_path(input_path(source))

    local buf, chan = ensure_column(source)
    local cmd = { 'just', mode, vim.fn.fnamemodify(source, ':t') }
    local action = mode == 'debug' and 'debugging' or 'compiling'
    notify(action .. '...')
    local job = vim.fn.jobstart(cmd, {
        cwd = vim.fn.fnamemodify(source, ':h'),
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = output_handler(chan),
        on_stderr = output_handler(chan),
        on_exit = function(_, code)
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].cp_job then
                    vim.b[buf].cp_job = nil
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
        vim.b[buf].cp_job = job
    end
end

function M.setup()
    local group = vim.api.nvim_create_augroup('Cp', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufWinLeave', 'BufWipeout', 'WinClosed' }, {
        group = group,
        callback = close_if_orphaned,
    })
    vim.api.nvim_create_autocmd('BufLeave', {
        group = group,
        pattern = '*.in',
        callback = function(args)
            if
                vim.bo[args.buf].modified
                and M.is_cp_path(vim.api.nvim_buf_get_name(args.buf))
            then
                vim.api.nvim_buf_call(args.buf, function()
                    vim.cmd.write()
                end)
            end
        end,
    })
    vim.api.nvim_create_autocmd('SessionLoadPost', {
        group = group,
        callback = function()
            vim.schedule(restore_column)
        end,
    })
    vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufReadPost' }, {
        group = group,
        callback = function(args)
            if M.is_cp_path(vim.api.nvim_buf_get_name(args.buf)) then
                vim.diagnostic.enable(false, { bufnr = args.buf })
            end
        end,
    })

    vim.api.nvim_create_user_command('CP', function(opts)
        local arg = opts.args == '' and 'run' or opts.args
        if arg == 'run' or arg == 'debug' then
            M.run(arg)
        else
            M.open_problem(arg)
        end
    end, {
        nargs = '?',
        complete = function(arg_lead)
            return complete_problem(arg_lead)
        end,
    })
    vim.keymap.set('n', '<leader>c', function()
        M.run('run')
    end, { desc = 'run CP problem' })
    vim.keymap.set('n', '<leader>d', function()
        M.run('debug')
    end, { desc = 'debug CP problem' })
end

return M
