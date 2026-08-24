-- https://github.com/echasnovski/mini.misc/blob/main/lua/mini/misc.lua#L838

---@type integer?
local zoom_winid = nil

---Editor row 0 is the tabline and the row above the cmdline is the global
---statusline, so a float spanning either end paints over it.
---@return vim.api.keyset.win_config
local function config()
    local tabline = vim.o.showtabline == 2
        or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
    local top = tabline and 1 or 0

    return {
        relative = 'editor',
        row = top,
        col = 0,
        width = vim.o.columns,
        height = vim.o.lines
            - vim.o.cmdheight
            - top
            - (vim.o.laststatus > 0 and 1 or 0),
        border = 'none',
    }
end

local function zoom()
    if zoom_winid and vim.api.nvim_win_is_valid(zoom_winid) then
        vim.api.nvim_win_close(zoom_winid, true)
        zoom_winid = nil
        return
    end
    zoom_winid = vim.api.nvim_open_win(0, true, config())
    vim.cmd('normal! zz')

    local group = vim.api.nvim_create_augroup('Zoom', { clear = true })
    local function refit()
        if not (zoom_winid and vim.api.nvim_win_is_valid(zoom_winid)) then
            return
        end
        vim.api.nvim_win_set_config(zoom_winid, config())
    end

    vim.api.nvim_create_autocmd('VimResized', {
        group = group,
        callback = refit,
    })
    vim.api.nvim_create_autocmd('OptionSet', {
        group = group,
        pattern = { 'showtabline', 'laststatus', 'cmdheight' },
        callback = refit,
    })
end

vim.keymap.set('n', '<c-w>m', zoom, { desc = 'toggle zoom' })
