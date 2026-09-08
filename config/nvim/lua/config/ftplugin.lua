-- NOTE: consider replacing if https://github.com/vim/vim/issues/21243 gets resolved
local M = {}

---@param options string[]
function M.undo_window_options(options)
    local buf = vim.api.nvim_get_current_buf()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == buf then
            for _, option in ipairs(options) do
                local value =
                    vim.api.nvim_get_option_value(option, { scope = 'global' })
                vim.api.nvim_set_option_value(
                    option,
                    value,
                    { scope = 'local', win = win }
                )
            end
        end
    end
end

return M
