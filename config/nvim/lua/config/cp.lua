local M = {}

M.root = vim.fs.normalize('~/dev/cp')

local languages = {
    cpp = { ext = '.cc', solve = '^%s*void%s+solve%(%).*{%s*$' },
    python = { ext = '.py', solve = '^%s*def%s+solve%(%).*:%s*$' },
}

local MODES = { 'run', 'debug', 'judge' }

local RATIO = 0.35
local CLEAR_POLL_MS = 10
local CLEAR_TIMEOUT_MS = 500

---@class cp.Column
---@field output? integer
---@field input? integer
---@field rest integer[]

---@param msg string
---@param level? integer
local function notify(msg, level)
    vim.notify('[cp]: ' .. msg, level or vim.log.levels.INFO)
end

---@return { ext: string, solve: string }?
---@return string
local function default_language()
    local name = (vim.g.cp or {}).language
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

---@param tp? integer
---@return cp.Column
local function column(tp)
    local cols = { rest = {} }
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp or 0)) do
        if vim.api.nvim_win_get_config(win).relative == '' then
            if vim.b[vim.api.nvim_win_get_buf(win)].cp_output then
                cols.output = win
            elseif vim.w[win].cp_input then
                cols.input = win
            else
                cols.rest[#cols.rest + 1] = win
            end
        end
    end
    return cols
end

---@param cols cp.Column
---@return integer
local function edit_win(cols)
    local cur = vim.api.nvim_get_current_win()
    if cur ~= cols.output and cur ~= cols.input then
        return cur
    end
    return cols.rest[1] or cur
end

---@param cols cp.Column
local function close_column(cols)
    if cols.output then
        local buf = vim.api.nvim_win_get_buf(cols.output)
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
            if (cols.output or cols.input) and #cols.rest == 0 then
                close_column(cols)
            end
        end
    end)
end

---@param win integer
---@param source string
---@return integer buf
local function reset_output(win, source)
    local live = vim.api.nvim_win_get_buf(win)
    if vim.b[live].cp_source == source and vim.b[live].terminal_job_id then
        return live
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].buflisted = false
    vim.b[buf].cp_output = true
    vim.b[buf].cp_source = source
    vim.b[buf].term_normal = true
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_call(win, function()
        vim.fn.jobstart({ vim.o.shell }, {
            term = true,
            cwd = vim.fn.fnamemodify(source, ':h'),
        })
    end)
    return buf
end

---@param output_win integer
---@param input_win integer
local function size_column(output_win, input_win)
    local rows = vim.api.nvim_win_get_height(output_win)
        + vim.api.nvim_win_get_height(input_win)
    vim.api.nvim_win_resize(output_win, math.floor(vim.o.columns * RATIO), -1)
    vim.api.nvim_win_resize(input_win, -1, math.floor(rows * RATIO))
end

---@param output_win integer
---@param source string
---@return integer input_win
local function attach_input(output_win, source)
    vim.api.nvim_set_current_win(output_win)
    vim.cmd('belowright split ' .. vim.fn.fnameescape(input_path(source)))
    local input_win = vim.api.nvim_get_current_win()
    vim.w[input_win].cp_input = true
    size_column(output_win, input_win)
    return input_win
end

---@param input_win integer
---@return integer output_win
local function attach_output(input_win)
    vim.api.nvim_set_current_win(input_win)
    vim.cmd('aboveleft split')
    local output_win = vim.api.nvim_get_current_win()
    size_column(output_win, input_win)
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
        output_win, input_win = open_column(edit_win(cols), source)
    end

    local buf = reset_output(output_win, source)
    retarget_input(input_win, source)

    if vim.api.nvim_win_is_valid(saved_win) then
        vim.api.nvim_set_current_win(saved_win)
        vim.fn.winrestview(saved_view)
    end
    return buf
end

---@return string?
local function resolve_source()
    local name = vim.api.nvim_buf_get_name(0)
    if languages[vim.bo.filetype] and M.is_cp_path(name) then
        return name
    end
    if is_input_path(name) then
        return source_for_input(name)
    end

    local cols = column()
    if cols.output then
        return vim.b[vim.api.nvim_win_get_buf(cols.output)].cp_source
    end
    if cols.input then
        return source_for_input(
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cols.input))
        )
    end
end

---@param wins integer[]
---@return integer?
local function claim_input(wins)
    for _, win in ipairs(wins) do
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
        if is_input_path(name) then
            vim.w[win].cp_input = true
            return win
        end
    end
end

local function restore_column()
    local cols = column()
    if cols.output then
        return
    end

    local input_win = cols.input or claim_input(cols.rest)
    if not input_win then
        return
    end

    local source = source_for_input(
        vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(input_win))
    )
    if not source then
        return
    end

    local saved_win = vim.api.nvim_get_current_win()
    local saved_view = vim.fn.winsaveview()
    reset_output(attach_output(input_win), source)
    if vim.api.nvim_win_is_valid(saved_win) then
        vim.api.nvim_set_current_win(saved_win)
        vim.fn.winrestview(saved_view)
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
    local items = vim.list_extend({}, MODES)
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

    vim.api.nvim_set_current_win(edit_win(column()))
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

---@alias cp.Url fun(round: string, problem: string): string
---@alias cp.Round fun(round: string, done: fun(contest: string))

local CONTEST_LIST = 'https://codeforces.com/api/contest.list?gym=false'

---@param round string
---@param done fun(contest: string)
local function codeforces_contest(round, done)
    vim.net.request(CONTEST_LIST, {}, function(err, response)
        vim.schedule(function()
            if err or not response then
                notify(err or 'no contest list', vim.log.levels.ERROR)
                return
            end
            local ok, list = pcall(vim.json.decode, response.body)
            if not ok or list.status ~= 'OK' then
                notify('malformed contest list', vim.log.levels.ERROR)
                return
            end

            local matches = {}
            for _, contest in ipairs(list.result) do
                local number = contest.name:match('Codeforces Round%s+(%d+)')
                    or contest.name:match('Codeforces Beta Round%s+(%d+)')
                if number and tonumber(number) == tonumber(round) then
                    matches[#matches + 1] = contest
                end
            end
            table.sort(matches, function(a, b)
                return a.name < b.name
            end)

            if #matches < 2 then
                done(matches[1] and tostring(matches[1].id) or round)
                return
            end
            vim.ui.select(matches, {
                prompt = 'Codeforces Round ' .. round,
                format_item = function(contest)
                    return contest.name
                end,
            }, function(contest)
                if contest then
                    done(tostring(contest.id))
                end
            end)
        end)
    end)
end

---@type table<string, { problem: cp.Url, submit?: cp.Url, round?: cp.Round }>
local judges = {
    atcoder = {
        problem = function(round, problem)
            return ('https://atcoder.jp/contests/%s/tasks/%s'):format(
                round,
                problem
            )
        end,
        submit = function(round, problem)
            return ('https://atcoder.jp/contests/%s/submit?taskScreenName=%s'):format(
                round,
                problem
            )
        end,
    },
    codeforces = {
        round = codeforces_contest,
        problem = function(round, problem)
            return ('https://codeforces.com/contest/%s/problem/%s'):format(
                round,
                problem:upper()
            )
        end,
        submit = function(round, problem)
            return ('https://codeforces.com/problemset/submit/%s/%s'):format(
                round,
                problem:upper()
            )
        end,
    },
    cses = {
        problem = function(_, problem)
            return ('https://cses.fi/problemset/task/%s'):format(problem)
        end,
    },
    kattis = {
        problem = function(_, problem)
            return ('https://open.kattis.com/problems/%s'):format(problem)
        end,
    },
    usaco = {
        problem = function(_, problem)
            return ('https://usaco.org/index.php?page=viewproblem2&cpid=%s'):format(
                problem
            )
        end,
    },
}

---@param kind 'problem'|'submit'
function M.open_url(kind)
    local source = resolve_source()
    if not source then
        notify('not in ~/dev/cp', vim.log.levels.ERROR)
        return
    end

    local parts = vim.split(vim.fs.relpath(M.root, source), '/')
    if #parts < 3 then
        notify('expected <judge>/<round>/<problem>', vim.log.levels.ERROR)
        return
    end
    local judge = judges[parts[1]]
    if not judge then
        notify('unknown judge: ' .. parts[1], vim.log.levels.ERROR)
        return
    end

    local problem = vim.fn.fnamemodify(parts[#parts], ':r')
    local function open(round)
        local url = (judge[kind] or judge.problem)(round, problem)
        local _, err = vim.ui.open(url)
        if err then
            notify(('%s: %s'):format(err, url), vim.log.levels.ERROR)
        end
    end

    if judge.round then
        judge.round(parts[#parts - 1], open)
    else
        open(parts[#parts - 1])
    end
end

---@param mode 'run'|'debug'|'judge'
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

    local buf = ensure_column(source)
    local job = vim.b[buf].terminal_job_id
    if not job then
        return
    end
    local cmd = ('just %s %s\r'):format(mode, vim.fn.fnamemodify(source, ':t'))
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    local timer = assert(vim.uv.new_timer())
    local waited = 0

    vim.api.nvim_chan_send(job, '\12')
    timer:start(
        CLEAR_POLL_MS,
        CLEAR_POLL_MS,
        vim.schedule_wrap(function()
            waited = waited + CLEAR_POLL_MS
            local settled = not vim.api.nvim_buf_is_valid(buf)
                or vim.api.nvim_buf_get_changedtick(buf) ~= tick
            if not settled and waited < CLEAR_TIMEOUT_MS then
                return
            end

            timer:stop()
            timer:close()
            if vim.api.nvim_buf_is_valid(buf) then
                pcall(vim.api.nvim_chan_send, job, cmd)
            end
        end)
    )
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
                vim.b[args.buf].minicompletion_config =
                    { delay = { signature = 10000000 } }
            end
        end,
    })

    vim.api.nvim_create_user_command('CP', function(opts)
        local arg = opts.args == '' and 'run' or opts.args
        if vim.tbl_contains(MODES, arg) then
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
    for _, mode in ipairs(MODES) do
        vim.keymap.set('n', '<Plug>(cp-' .. mode .. ')', function()
            M.run(mode)
        end, { desc = mode .. ' CP problem' })
    end
    vim.keymap.set('n', '<Plug>(cp-problem)', function()
        M.open_url('problem')
    end, { desc = 'open CP problem' })
    vim.keymap.set('n', '<Plug>(cp-submit)', function()
        M.open_url('submit')
    end, { desc = 'open CP submission' })
end

return M
