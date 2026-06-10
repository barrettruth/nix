local M = {}

local review_prefix = 'diffs://review:'

local numberless_ft = {
    fzf = true,
    TelescopePrompt = true,
    TelescopeResults = true,
}

local function numbers_off(buf)
    if vim.bo[buf].buftype == 'terminal' then
        return true
    end
    if numberless_ft[vim.bo[buf].filetype] then
        return true
    end
    if vim.startswith(vim.api.nvim_buf_get_name(buf), review_prefix) then
        return true
    end
    return false
end

function M.apply(win)
    win = win or vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(win) then
        return
    end
    if vim.api.nvim_win_get_config(win).relative ~= '' then
        return
    end
    local buf = vim.api.nvim_win_get_buf(win)
    local on = not numbers_off(buf)
    vim.wo[win][0].number = on and vim.go.number
    vim.wo[win][0].relativenumber = on and vim.go.relativenumber
end

function M.render()
    if vim.v.virtnum ~= 0 then
        return ''
    end

    if vim.bo.buftype == 'terminal' then
        return ''
    end

    local column = '%s%C '

    if not vim.wo.number and not vim.wo.relativenumber then
        return column
    end

    return column .. '%=%{v:relnum?v:relnum:v:lnum} '
end

function M.setup()
    vim.o.statuscolumn = "%{%v:lua.require'config.statuscolumn'.render()%}"

    local aug = vim.api.nvim_create_augroup('StatusColumn', { clear = true })

    vim.api.nvim_create_autocmd({
        'BufEnter',
        'BufFilePost',
        'BufWinEnter',
        'WinEnter',
        'TermOpen',
        'FileType',
    }, {
        group = aug,
        callback = function()
            M.apply(vim.api.nvim_get_current_win())
        end,
    })

    M.apply(vim.api.nvim_get_current_win())
end

return M
