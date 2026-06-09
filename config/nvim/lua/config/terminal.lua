local M = {}

function M.nav(dir)
    pcall(vim.api.nvim_win_set_cursor, 0, { vim.api.nvim_buf_line_count(0), 0 })
    vim.cmd.wincmd(dir)
    if vim.bo.buftype == 'terminal' then
        vim.cmd.startinsert()
    end
end

return M
