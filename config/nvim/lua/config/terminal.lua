local M = {}

-- Called by the <c-s-hjkl> *terminal-mode* maps, after <c-\><c-n> has dropped us
-- into normal mode. devin's cursor sits on the second-to-last line, so Neovim's
-- "tail if cursor is on the last line" rule never fires on its own; we pin the
-- terminal we're leaving to its true last line so it keeps following output
-- while unfocused, move to the target window, and re-enter terminal mode if we
-- land on another terminal. Navigating from *normal* mode uses a plain <c-w>
-- map instead, so a deliberately-scrolled terminal is left exactly as-is.
function M.nav(dir)
    pcall(vim.api.nvim_win_set_cursor, 0, { vim.api.nvim_buf_line_count(0), 0 })
    vim.cmd.wincmd(dir)
    if vim.bo.buftype == 'terminal' then
        vim.cmd.startinsert()
    end
end

return M
