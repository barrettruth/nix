local M = {}

M.root = vim.fn.expand('~/dev/cp')
M.root_pattern = '^' .. vim.pesc(M.root) .. '/'

M.cxx_flags = {
    '-std=c++23',
    '-O2',
    '-Wall',
    '-Wextra',
    '-Wpedantic',
    '-Wshadow',
    '-Wconversion',
    '-Wformat=2',
    '-Wfloat-equal',
    '-Wundef',
    '-fdiagnostics-color=always',
    '-DLOCAL',
}

---@param path string?
---@return boolean
function M.is_cp_path(path)
    if not path or path == '' then
        return false
    end
    path = vim.fn.fnamemodify(path, ':p'):gsub('/$', '')
    return path == M.root or path:sub(1, #M.root + 1) == M.root .. '/'
end

---@param source string
---@return string
local function binary_path(source)
    return vim.fn.fnamemodify(source, ':r') .. '.run'
end

---@param source string
---@return string
local function input_path(source)
    return vim.fn.fnamemodify(source, ':r') .. '.in'
end

---@class cp.Command
---@field compile_args string[]
---@field compile_text string
---@field run_text string
---@field tmp_name string
---@field bin_name string
---@field input_name string

---@param source string
---@param bin string
---@param input string
---@return cp.Command
local function commands(source, bin, input)
    local source_name = vim.fn.fnamemodify(source, ':t')
    local bin_name = vim.fn.fnamemodify(bin, ':t')
    local input_name = vim.fn.fnamemodify(input, ':t')
    local tmp_name = ('%s.tmp.%d'):format(bin_name, vim.fn.getpid())
    local compile = vim.list_extend({ 'g++' }, vim.deepcopy(M.cxx_flags))
    vim.list_extend(compile, { source_name, '-o', tmp_name })
    return {
        compile_args = compile,
        compile_text = table.concat(compile, ' '),
        run_text = ('./%s < %s'):format(bin_name, input_name),
        tmp_name = tmp_name,
        bin_name = bin_name,
        input_name = input_name,
    }
end

---@param chan integer
---@param data string
local function term_send(chan, data)
    if data == '' then
        return
    end
    data = data:gsub('\n', '\r\n')
    local send = function()
        pcall(vim.api.nvim_chan_send, chan, data)
    end
    if vim.in_fast_event() then
        vim.schedule(send)
    else
        send()
    end
end

---@param chan integer
---@return fun(_: integer, data: string[])
local function output_handler(chan)
    return function(_, data)
        if data and not (#data == 1 and data[1] == '') then
            term_send(chan, table.concat(data, '\n'))
        end
    end
end

---@param dir string
---@param chan integer
---@param cmd cp.Command
local function run_program(dir, chan, cmd)
    term_send(chan, '\n> ' .. cmd.run_text .. '\n')
    local input_path_abs = vim.fs.joinpath(dir, cmd.input_name)
    if vim.fn.filereadable(input_path_abs) ~= 1 then
        term_send(chan, 'cp: missing input ' .. cmd.input_name .. '\n')
        return
    end
    local job = vim.fn.jobstart({ vim.fs.joinpath(dir, cmd.bin_name) }, {
        cwd = dir,
        stdin = 'pipe',
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = output_handler(chan),
        on_stderr = output_handler(chan),
    })
    if job <= 0 then
        term_send(chan, 'cp: failed to run ' .. cmd.bin_name .. '\n')
        return
    end
    local input = table.concat(vim.fn.readfile(input_path_abs, 'b'), '\n')
    if input ~= '' then
        vim.fn.chansend(job, input .. '\n')
    end
    vim.fn.chanclose(job, 'stdin')
end

---@param dir string
---@param chan integer
---@param cmd cp.Command
local function run_compile(dir, chan, cmd)
    term_send(chan, '> ' .. cmd.compile_text .. '\n')
    local job = vim.fn.jobstart(cmd.compile_args, {
        cwd = dir,
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = output_handler(chan),
        on_stderr = output_handler(chan),
        on_exit = function(_, code)
            vim.schedule(function()
                local tmp = vim.fs.joinpath(dir, cmd.tmp_name)
                local bin = vim.fs.joinpath(dir, cmd.bin_name)
                if code ~= 0 then
                    pcall(vim.fn.delete, tmp)
                    return
                end
                if vim.fn.rename(tmp, bin) ~= 0 then
                    term_send(
                        chan,
                        'cp: failed to write ' .. cmd.bin_name .. '\n'
                    )
                    return
                end
                run_program(dir, chan, cmd)
            end)
        end,
    })
    if job <= 0 then
        term_send(chan, 'cp: failed to start g++\n')
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

---@param source string
---@param dir string
---@param cmd cp.Command
local function run_terminal(source, dir, cmd)
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
    run_compile(dir, chan, cmd)
end

function M.run()
    local source = vim.api.nvim_buf_get_name(0)
    if not M.is_cp_path(source) then
        vim.notify('[cp]: not in ~/dev/cp', vim.log.levels.WARN)
        return
    end
    if vim.bo.filetype ~= 'cpp' then
        vim.notify('[cp]: only C++ files are supported', vim.log.levels.WARN)
        return
    end
    if vim.bo.modified then
        vim.cmd.write()
    end

    local bin = binary_path(source)
    local input = input_path(source)
    run_terminal(
        source,
        vim.fn.fnamemodify(source, ':h'),
        commands(source, bin, input)
    )
end

function M.setup()
    vim.api.nvim_create_user_command('CP', M.run, {})
    vim.keymap.set('n', '<c-p>', '<cmd>CP<cr>', { desc = 'run CP problem' })
end

return M
