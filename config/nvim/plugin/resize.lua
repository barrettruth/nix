-- Scale windows with the screen, which Nvim only offers as `wincmd =`.

local aug = vim.api.nvim_create_augroup('Resize', { clear = true })

---@type table<integer, table<integer, [number, number]>>
local tab_ratios = {}
local cols, lines = vim.o.columns, vim.o.lines
local applying = false

---@param tab integer
---@return integer[] wins, integer width, integer height
local function layout(tab)
    local wins = {}
    local top, left = math.huge, math.huge
    local bottom, right = 0, 0

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_get_config(win).relative == '' then
            local pos = vim.api.nvim_win_get_position(win)
            wins[#wins + 1] = win
            top = math.min(top, pos[1])
            left = math.min(left, pos[2])
            bottom = math.max(bottom, pos[1] + vim.api.nvim_win_get_height(win))
            right = math.max(right, pos[2] + vim.api.nvim_win_get_width(win))
        end
    end

    return wins, math.max(1, right - left), math.max(1, bottom - top)
end

local function capture_ratios()
    if applying or vim.o.columns ~= cols or vim.o.lines ~= lines then
        return
    end

    local tab = vim.api.nvim_get_current_tabpage()
    local wins, width, height = layout(tab)
    local ratios = {}
    for _, win in ipairs(wins) do
        ratios[win] = {
            vim.api.nvim_win_get_width(win) / width,
            vim.api.nvim_win_get_height(win) / height,
        }
    end
    tab_ratios[tab] = ratios
end

capture_ratios()

vim.api.nvim_create_autocmd({ 'WinResized', 'TabEnter' }, {
    group = aug,
    callback = capture_ratios,
})

vim.api.nvim_create_autocmd('VimResized', {
    group = aug,
    callback = function()
        applying = true
        for tab, ratios in pairs(tab_ratios) do
            if vim.api.nvim_tabpage_is_valid(tab) then
                local wins, width, height = layout(tab)
                for _, win in ipairs(wins) do
                    local ratio = ratios[win]
                    if ratio then
                        pcall(
                            vim.api.nvim_win_resize,
                            win,
                            math.max(1, math.floor(ratio[1] * width + 0.5)),
                            math.max(1, math.floor(ratio[2] * height + 0.5))
                        )
                    end
                end
            else
                tab_ratios[tab] = nil
            end
        end
        cols, lines = vim.o.columns, vim.o.lines
        vim.schedule(function()
            applying = false
        end)
    end,
})
