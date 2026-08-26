local M = {}

-- diffs.nvim review buffer $refix
local review_prefix = 'diffs://review:'

local numberless_ft = {
    fzf = true,
    TelescopePrompt = true,
    TelescopeResults = true,
}

---@type boolean
local git = false

---@param buf integer
---@return boolean
local function columnless(buf)
    return vim.bo[buf].buftype == 'terminal'
        or vim.bo[buf].filetype == 'cpinput'
end

---@param buf integer
---@return boolean
local function numbers_off(buf)
    if columnless(buf) then
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

---@param win? integer defaults to the current window
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

---@return string
function M.render()
    if vim.v.virtnum ~= 0 then
        return ''
    end

    if columnless(0) then
        return ''
    end

    local signs = git and require('gitsigns').statuscolumn() or ''
    local column = signs .. '%C '

    if not vim.wo.number and not vim.wo.relativenumber then
        return column
    end

    return column .. '%=%{v:relnum?v:relnum:v:lnum} '
end

---@return nil
function M.toggle_git()
    git = not git
    if git then
        require('gitsigns').refresh()
    end
    vim.api.nvim__redraw({ statuscolumn = true })
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
