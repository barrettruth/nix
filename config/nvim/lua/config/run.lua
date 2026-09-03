local M = {}

local RATIO = 0.35
local DIAGNOSTIC_NAMESPACE = vim.api.nvim_create_namespace('run')
local DEFAULT_PUBLISH = { 'quickfix' }

---@type vim.SystemObj?
local building = nil

---@type integer?
local group = nil

---@param buf integer
---@return table
local function buffer_run(buf)
    local value = vim.b[buf].run
    if type(value) == 'table' then
        return value
    end
    if type(value) == 'string' then
        return { command = value }
    end
    return {}
end

---@param buf integer
---@return string?
local function run_command(buf)
    local command = buffer_run(buf).command
    return type(command) == 'string' and command or nil
end

---@param msg string
local function log(msg)
    vim.api.nvim_echo({ { 'run: ' .. msg } }, true, {})
end

---@param msg string
local function fail(msg)
    vim.notify('run: ' .. msg, vim.log.levels.ERROR)
end

---@param buf integer
---@return string[]
local function publishers(buf)
    local buffer = buffer_run(buf)
    if buffer.publish ~= nil then
        return buffer.publish
    end

    local global = vim.g.run
    if type(global) == 'table' and global.publish ~= nil then
        return global.publish
    end

    return DEFAULT_PUBLISH
end

---@param buf integer
---@param name string
---@return boolean
local function publishes(buf, name)
    return vim.tbl_contains(publishers(buf), name)
end

---@param buf integer
---@return string
local function no_runner(buf)
    local ft = vim.bo[buf].filetype
    return 'no runner for ' .. (ft ~= '' and ft or 'this buffer')
end

---@param buf integer
---@return boolean
local function enabled(buf)
    return group ~= nil
        and vim.api.nvim_buf_is_valid(buf)
        and #vim.api.nvim_get_autocmds({
                group = group,
                event = 'BufWritePost',
                buf = buf,
            })
            > 0
end

---@param win integer
---@return boolean
local function is_output(win)
    return vim.b[vim.api.nvim_win_get_buf(win)].run_output == true
end

---@param tp integer
---@param skip? integer
---@return integer[] outputs
---@return integer others
local function survey(tp, skip)
    local outputs, others = {}, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        if vim.api.nvim_win_get_config(win).relative == '' and win ~= skip then
            if is_output(win) then
                outputs[#outputs + 1] = win
            else
                others = others + 1
            end
        end
    end
    return outputs, others
end

---@return integer?
local function output_win()
    local outputs = survey(0)
    return outputs[1]
end

---@param buf integer
---@param tp integer
---@return boolean
local function displayed(buf, tp)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        if vim.api.nvim_win_get_buf(win) == buf then
            return true
        end
    end
    return false
end

---@param source? integer
local function close_outputs(source)
    local closing = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local outputs = survey(tp)
        for _, win in ipairs(outputs) do
            local src = vim.b[vim.api.nvim_win_get_buf(win)].run_source
            local kept = src
                and src ~= source
                and vim.api.nvim_buf_is_valid(src)
                and displayed(src, tp)
            if not kept then
                closing[#closing + 1] = win
            end
        end
    end
    for _, win in ipairs(closing) do
        if
            vim.api.nvim_win_is_valid(win)
            and not pcall(vim.api.nvim_win_close, win, true)
        then
            pcall(vim.api.nvim_win_call, win, vim.cmd.quit)
        end
    end
end

---@param win integer
---@param fn function
local function win_call(win, fn)
    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, fn)
    end
end

---@param win integer
---@param title string
---@param items table[]
---@return integer count
local function publish_quickfix(win, title, items)
    if #items == 0 then
        return 0
    end

    vim.fn.setqflist({}, ' ', { title = title, items = items })
    win_call(win, function()
        vim.cmd('botright copen')
    end)
    return #items
end

---@param items table[]
---@return integer count
local function publish_diagnostics(items)
    local severity = {
        E = vim.diagnostic.severity.ERROR,
        W = vim.diagnostic.severity.WARN,
        I = vim.diagnostic.severity.INFO,
        N = vim.diagnostic.severity.HINT,
    }
    local by_buffer = {}
    local count = 0

    for _, item in ipairs(items) do
        if item.valid == 1 and item.bufnr > 0 and item.lnum > 0 then
            by_buffer[item.bufnr] = by_buffer[item.bufnr] or {}
            table.insert(by_buffer[item.bufnr], {
                lnum = item.lnum - 1,
                col = math.max(item.col - 1, 0),
                message = item.text,
                severity = severity[item.type] or vim.diagnostic.severity.ERROR,
                source = 'build',
            })
            count = count + 1
        end
    end

    for buf, diagnostics in pairs(by_buffer) do
        vim.diagnostic.set(DIAGNOSTIC_NAMESPACE, buf, diagnostics)
    end

    return count
end

---@param source integer
---@param win integer
---@param title string
---@param lines string[]
---@param efm string
---@return integer count
local function publish(source, win, title, lines, efm)
    local items = vim.fn.getqflist({ lines = lines, efm = efm }).items
    local count = 0

    for _, publisher in ipairs(publishers(source)) do
        if publisher == 'quickfix' then
            count = math.max(count, publish_quickfix(win, title, items))
        elseif publisher == 'diagnostics' then
            count = math.max(count, publish_diagnostics(items))
        end
    end

    return count
end

---@param source integer
---@param cmd string
local function terminal(source, cmd)
    local saved = vim.api.nvim_get_current_win()
    local win = output_win()
    if win then
        vim.api.nvim_set_current_win(win)
    else
        vim.cmd(
            ('botright vertical %d split'):format(
                math.floor(vim.o.columns * RATIO)
            )
        )
        win = vim.api.nvim_get_current_win()
        vim.wo[win].winfixwidth = true
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.b[buf].run_output = true
    vim.b[buf].run_source = source
    vim.b[buf].term_normal = true
    vim.api.nvim_win_set_buf(win, buf)

    log('running...')
    vim.fn.jobstart(cmd, {
        term = true,
        on_exit = function(_, code)
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) then
                    log(('exit %d'):format(code))
                end
            end)
        end,
    })

    if vim.api.nvim_win_is_valid(saved) then
        vim.api.nvim_set_current_win(saved)
    end
end

---@param buf integer
---@param win integer
local function launch(buf, win)
    local efm = vim.bo[buf].errorformat
    local command = run_command(buf)
    if not command then
        return
    end
    local run, build
    vim.api.nvim_buf_call(buf, function()
        run = vim.fn.expandcmd(command)
        build = vim.bo.makeprg ~= '' and vim.fn.expandcmd(vim.bo.makeprg)
    end)

    local function start()
        if not enabled(buf) or not run_command(buf) then
            return
        end
        win_call(win, function()
            if publishes(buf, 'quickfix') then
                vim.cmd.cclose()
            end
            terminal(buf, run)
        end)
    end

    if not build then
        return start()
    end

    log('building...')
    vim.diagnostic.reset(DIAGNOSTIC_NAMESPACE)
    local job
    job = vim.system(
        { '/bin/sh', '-c', 'exec ' .. build },
        { text = true },
        function(out)
            vim.schedule(function()
                if building ~= job then
                    return
                end
                building = nil

                if out.code == 0 then
                    return start()
                end

                local lines =
                    vim.split((out.stdout or '') .. (out.stderr or ''), '\n', {
                        trimempty = true,
                    })
                local count = publish(buf, win, build, lines, efm)
                if count == 0 then
                    fail(
                        #lines > 0 and table.concat(lines, '\n')
                            or ('build exited %d'):format(out.code)
                    )
                else
                    log(
                        ('build failed, %d error%s'):format(
                            count,
                            count == 1 and '' or 's'
                        )
                    )
                end
            end)
        end
    )
    building = job
end

---@param buf? integer
---@param win? integer
function M.run(buf, win)
    buf = buf or vim.api.nvim_get_current_buf()
    win = win or vim.api.nvim_get_current_win()
    if not enabled(buf) then
        return
    end
    if not run_command(buf) then
        fail(no_runner(buf))
        return
    end
    if vim.bo[buf].modified then
        return vim.api.nvim_buf_call(buf, vim.cmd.write)
    end

    if building then
        building:kill('sigterm')
        building = nil
    end
    launch(buf, win)
end

---@param buf integer
local function enable(buf)
    if enabled(buf) then
        return
    end
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = group,
        buffer = buf,
        callback = function(args)
            local id = args.id
            local win = vim.api.nvim_get_current_win()
            vim.schedule(function()
                if #vim.api.nvim_get_autocmds({ id = id }) > 0 then
                    M.run(args.buf, win)
                end
            end)
        end,
    })
end

---@param buf? integer
function M.disable(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not run_command(buf) then
        log(no_runner(buf))
        return
    end
    vim.api.nvim_clear_autocmds({
        group = group,
        event = 'BufWritePost',
        buf = buf,
    })
    close_outputs(buf)
    log('disabled')
end

function M.setup()
    group = vim.api.nvim_create_augroup('Run', { clear = true })

    vim.api.nvim_create_autocmd('QuitPre', {
        group = group,
        callback = function()
            local cur = vim.api.nvim_get_current_win()
            if vim.v.exiting ~= vim.NIL or is_output(cur) then
                return
            end
            local outputs, others = survey(0, cur)
            if others > 0 then
                return
            end
            for _, win in ipairs(outputs) do
                pcall(vim.api.nvim_win_close, win, true)
            end
        end,
    })
    vim.api.nvim_create_autocmd({ 'WinClosed', 'BufWinLeave' }, {
        group = group,
        callback = function()
            if vim.v.exiting ~= vim.NIL then
                return
            end
            vim.schedule(close_outputs)
        end,
    })

    vim.keymap.set('n', '<Plug>(run)', function()
        local buf = vim.api.nvim_get_current_buf()
        if not run_command(buf) then
            fail(no_runner(buf))
            return
        end
        enable(buf)
        M.run(buf)
    end, { desc = 'build and run the current file' })
    vim.keymap.set('n', '<Plug>(run-disable)', function()
        M.disable()
    end, { desc = 'disable the runner for the current file' })
end

return M
