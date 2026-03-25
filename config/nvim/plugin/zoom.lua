-- https://github.com/echasnovski/mini.misc/blob/main/lua/mini/misc.lua#L838

---@type integer?
local zoom_winid = nil

local function zoom()
    if zoom_winid and vim.api.nvim_win_is_valid(zoom_winid) then
        vim.api.nvim_win_close(zoom_winid, true)
        zoom_winid = nil
        return
    end
    local cfg = {
        relative = 'editor',
        row = 0,
        col = 0,
        width = vim.o.columns,
        height = vim.o.lines - vim.o.cmdheight,
        border = 'none',
    }
    zoom_winid = vim.api.nvim_open_win(0, true, cfg)
    vim.cmd('normal! zz')
    vim.api.nvim_create_autocmd('VimResized', {
        group = vim.api.nvim_create_augroup('Zoom', { clear = true }),
        callback = function()
            if not (zoom_winid and vim.api.nvim_win_is_valid(zoom_winid)) then
                return
            end
            vim.api.nvim_win_set_config(zoom_winid, {
                relative = 'editor',
                row = 0,
                col = 0,
                width = vim.o.columns,
                height = vim.o.lines - vim.o.cmdheight,
            })
        end,
    })
end

vim.keymap.set('n', '<c-w>m', zoom, { desc = 'toggle zoom' })
