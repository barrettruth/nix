-- Scale windows with the screen, which Nvim only offers as `wincmd =`.

local aug = vim.api.nvim_create_augroup('Resize', { clear = true })

local ratios, cols, lines = {}, vim.o.columns, vim.o.lines
local applying = false

---@return integer
local function usable()
    local tabline = vim.o.showtabline == 2
        or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)

    return math.max(
        1,
        vim.o.lines
            - vim.o.cmdheight
            - (tabline and 1 or 0)
            - (vim.o.laststatus > 0 and 1 or 0)
    )
end

local function capture_ratios()
    if applying or vim.o.columns ~= cols or vim.o.lines ~= lines then
        return
    end
    local rows = usable()
    ratios = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
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
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local ratio = ratios[win]
            if ratio then
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
