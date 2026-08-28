local M = {}

local RATIO = 0.35

---@type vim.SystemObj?
local building = nil

---@param msg string
local function log(msg)
    vim.api.nvim_echo({ { 'run: ' .. msg } }, true, {})
end

---@param msg string
local function fail(msg)
    vim.notify('run: ' .. msg, vim.log.levels.ERROR)
end

---@return integer?
local function output_win()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if
            vim.api.nvim_win_get_config(win).relative == ''
            and vim.b[vim.api.nvim_win_get_buf(win)].run_output
        then
            return win
        end
    end
end

---@param title string
---@param lines string[]
---@param efm string
---@return integer count
local function report(title, lines, efm)
    local items = vim.fn.getqflist({ lines = lines, efm = efm }).items
    if #items == 0 then
        return 0
    end

    vim.fn.setqflist({}, ' ', { title = title, items = items })
    local saved = vim.api.nvim_get_current_win()
    vim.cmd('botright copen')
    if vim.api.nvim_win_is_valid(saved) then
        vim.api.nvim_set_current_win(saved)
    end
    return #items
end

---@param cmd string
---@param efm string
local function terminal(cmd, efm)
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
    vim.b[buf].term_normal = true
    vim.api.nvim_win_set_buf(win, buf)

    local errors = vim.fn.tempname()
    log('running...')
    vim.fn.jobstart(('%s 2> %s'):format(cmd, vim.fn.shellescape(errors)), {
        term = true,
        on_exit = function(_, code)
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) then
                    if code ~= 0 then
                        report(cmd, vim.fn.readfile(errors), efm)
                    end
                    log(('exit %d'):format(code))
                end
                vim.fn.delete(errors)
            end)
        end,
    })

    if vim.api.nvim_win_is_valid(saved) then
        vim.api.nvim_set_current_win(saved)
    end
end

---@param buf integer
local function launch(buf)
    local efm = vim.bo[buf].errorformat
    local run, build
    vim.api.nvim_buf_call(buf, function()
        run = vim.fn.expandcmd(vim.b[buf].run)
        build = vim.bo.makeprg ~= '' and vim.fn.expandcmd(vim.bo.makeprg)
    end)

    local function start()
        vim.cmd.cclose()
        terminal(run, efm)
    end

    if not build then
        return start()
    end

    log('building...')
    local job
    job = vim.system(
        { vim.o.shell, vim.o.shellcmdflag, 'exec ' .. build },
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
                local count = report(build, lines, efm)
                if count == 0 then
                    fail(('build exited %d'):format(out.code))
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
function M.run(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.b[buf].run then
        local ft = vim.bo[buf].filetype
        fail('no runner for ' .. (ft ~= '' and ft or 'this buffer'))
        return
    end
    if vim.bo[buf].modified then
        return vim.api.nvim_buf_call(buf, vim.cmd.write)
    end

    if building then
        building:kill('sigterm')
        building = nil
    end
    launch(buf)
end

function M.setup()
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = vim.api.nvim_create_augroup('Run', { clear = true }),
        callback = function(args)
            if vim.b[args.buf].run then
                vim.schedule(function()
                    M.run(args.buf)
                end)
            end
        end,
    })

    vim.keymap.set('n', '<Plug>(run)', function()
        M.run()
    end, { desc = 'build and run the current file' })
end

return M
