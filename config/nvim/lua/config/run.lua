local M = {}

local RATIO = 0.35

---@param msg string
---@param level? integer
local function notify(msg, level)
    vim.notify('[run]: ' .. msg, level or vim.log.levels.INFO)
end

---@return integer
local function width()
    return math.floor(vim.o.columns * RATIO)
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
---@param code integer
local function report(title, lines, efm, code)
    if #lines == 0 then
        notify(('exited %d'):format(code), vim.log.levels.ERROR)
        return
    end

    vim.fn.setqflist({}, ' ', {
        title = title,
        items = vim.fn.getqflist({ lines = lines, efm = efm }).items,
    })

    local saved = vim.api.nvim_get_current_win()
    local out = output_win()
    if out then
        vim.api.nvim_set_current_win(out)
        vim.cmd(
            ('belowright copen %d'):format(
                math.floor(vim.api.nvim_win_get_height(out) * RATIO)
            )
        )
    else
        vim.cmd(('botright vertical %d copen'):format(width()))
        vim.wo.winfixwidth = true
    end
    if vim.api.nvim_win_is_valid(saved) then
        vim.api.nvim_set_current_win(saved)
    end
end

---@param cmd string
---@param efm string
local function terminal(cmd, efm)
    local saved = vim.api.nvim_get_current_win()
    local win = output_win()
    if win then
        vim.api.nvim_set_current_win(win)
    else
        vim.cmd(('botright vertical %d split'):format(width()))
        win = vim.api.nvim_get_current_win()
        vim.wo[win].winfixwidth = true
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.b[buf].run_output = true
    vim.api.nvim_win_set_buf(win, buf)

    local errors = vim.fn.tempname()
    vim.fn.jobstart(('%s 2> %s'):format(cmd, vim.fn.shellescape(errors)), {
        term = true,
        on_exit = function(_, code)
            vim.schedule(function()
                local lines = vim.fn.readfile(errors)
                vim.fn.delete(errors)
                if code ~= 0 then
                    report(cmd, lines, efm, code)
                end
            end)
        end,
    })

    if vim.api.nvim_win_is_valid(saved) then
        vim.api.nvim_set_current_win(saved)
    end
end

---@param args string
function M.run(args)
    local buf = vim.api.nvim_get_current_buf()
    local cmd = vim.b[buf].run
    if not cmd then
        local ft = vim.bo[buf].filetype
        notify(
            'no runner for ' .. (ft ~= '' and ft or 'this buffer'),
            vim.log.levels.ERROR
        )
        return
    end

    vim.cmd.update()

    local efm = vim.bo[buf].errorformat
    local run = vim.trim(vim.fn.expandcmd(cmd) .. ' ' .. args)
    local build = vim.bo[buf].makeprg ~= ''
        and vim.fn.expandcmd(vim.bo[buf].makeprg)

    if not build then
        vim.cmd.cclose()
        terminal(run, efm)
        return
    end

    vim.system(
        { vim.o.shell, vim.o.shellcmdflag, build },
        { text = true },
        function(out)
            vim.schedule(function()
                if out.code == 0 then
                    vim.cmd.cclose()
                    terminal(run, efm)
                    return
                end
                local lines =
                    vim.split((out.stdout or '') .. (out.stderr or ''), '\n', {
                        trimempty = true,
                    })
                report(build, lines, efm, out.code)
            end)
        end
    )
end

function M.setup()
    vim.api.nvim_create_user_command('Run', function(opts)
        M.run(opts.args)
    end, { nargs = '*', desc = 'build and run the current file' })

    vim.keymap.set('n', '<Plug>(run)', function()
        M.run('')
    end, { desc = 'build and run the current file' })
end

return M
