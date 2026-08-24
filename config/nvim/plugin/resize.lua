local aug = vim.api.nvim_create_augroup('Resize', { clear = true })

local ratios, cols, lines = {}, vim.o.columns, vim.o.lines
local applying = false

---@return integer
local function usable()
    local top, bottom = vim.o.lines, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == '' then
            local row = vim.api.nvim_win_get_position(win)[1]
            top = math.min(top, row)
            bottom = math.max(bottom, row + vim.api.nvim_win_get_height(win))
        end
    end
    return math.max(1, bottom - top)
end

local function capture_ratios()
    if applying or vim.o.columns ~= cols or vim.o.lines ~= lines then
        return
    end
    local rows = usable()
    ratios = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative == '' then
            ratios[win] = {
                vim.api.nvim_win_get_width(win) / cols,
                vim.api.nvim_win_get_height(win) / rows,
            }
        end
    end
end

vim.api.nvim_create_autocmd({ 'WinResized', 'WinNew', 'WinClosed' }, {
    group = aug,
    callback = capture_ratios,
})

vim.api.nvim_create_autocmd('VimResized', {
    group = aug,
    callback = function()
        applying = true
        local rows = usable()
        for win, ratio in pairs(ratios) do
            if vim.api.nvim_win_is_valid(win) then
                pcall(
                    vim.api.nvim_win_resize,
                    win,
                    math.max(1, math.floor(ratio[1] * vim.o.columns + 0.5)),
                    math.max(1, math.floor(ratio[2] * rows + 0.5))
                )
            end
        end
        cols, lines = vim.o.columns, vim.o.lines
        vim.schedule(function()
            applying = false
        end)
    end,
})
