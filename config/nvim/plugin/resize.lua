-- Scale windows with the screen, which Nvim only offers as `wincmd =`.

local aug = vim.api.nvim_create_augroup('Resize', { clear = true })

---@class ResizeSnapshot
---@field columns integer
---@field lines integer
---@field ratios table<integer, [number, number]>

---@type table<integer, ResizeSnapshot>
local tab_ratios = {}
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

---@param snapshot ResizeSnapshot
---@return boolean
local function same_screen(snapshot)
    return snapshot.columns == vim.o.columns and snapshot.lines == vim.o.lines
end

local function capture_ratios()
    local tab = vim.api.nvim_get_current_tabpage()
    local snapshot = tab_ratios[tab]
    if applying or (snapshot and not same_screen(snapshot)) then
        return
    end

    local wins, width, height = layout(tab)
    local ratios = {}
    for _, win in ipairs(wins) do
        ratios[win] = {
            vim.api.nvim_win_get_width(win) / width,
            vim.api.nvim_win_get_height(win) / height,
        }
    end
    tab_ratios[tab] = {
        columns = vim.o.columns,
        lines = vim.o.lines,
        ratios = ratios,
    }
end

local function resize()
    local tab = vim.api.nvim_get_current_tabpage()
    local snapshot = tab_ratios[tab]
    if not snapshot or same_screen(snapshot) then
        capture_ratios()
        return
    end

    local wins, width, height = layout(tab)
    local ratios = snapshot.ratios
    applying = true
    if
        #wins ~= vim.tbl_count(ratios)
        or vim.iter(wins):any(function(win)
            return ratios[win] == nil
        end)
    then
        tab_ratios[tab] = nil
    else
        for _, win in ipairs(wins) do
            local ratio = ratios[win]
            local win_width = vim.api.nvim_win_get_width(win) == width and -1
                or math.max(1, math.floor(ratio[1] * width + 0.5))
            local win_height = vim.api.nvim_win_get_height(win) == height and -1
                or math.max(1, math.floor(ratio[2] * height + 0.5))
            if win_width ~= -1 or win_height ~= -1 then
                pcall(vim.api.nvim_win_resize, win, win_width, win_height)
            end
        end
        snapshot.columns, snapshot.lines = vim.o.columns, vim.o.lines
    end
    vim.schedule(function()
        applying = false
    end)
end

capture_ratios()

vim.api.nvim_create_autocmd('WinResized', {
    group = aug,
    callback = capture_ratios,
})

vim.api.nvim_create_autocmd({ 'VimResized', 'TabEnter' }, {
    group = aug,
    callback = resize,
})

vim.api.nvim_create_autocmd('TabClosed', {
    group = aug,
    callback = function()
        for tab in pairs(tab_ratios) do
            if not vim.api.nvim_tabpage_is_valid(tab) then
                tab_ratios[tab] = nil
            end
        end
    end,
})
