vim.opt.complete = { 'o', '.', 'w', 'b' }
vim.o.completefunc = "v:lua.require'config.completion'.complete"
vim.opt.completeopt = { 'menuone', 'noinsert', 'popup', 'fuzzy' }

vim.o.autocomplete = false
vim.o.pumborder = 'single'
vim.o.pumheight = 15
vim.o.pumwidth = 24
vim.o.pummaxwidth = 80

local function current_preview_winid()
    local info = vim.fn.complete_info({ 'preview_winid' })
    return info.preview_winid or 0
end

---@param direction 'up'|'down'
---@return boolean scrolled
local function scroll_preview(direction)
    local winid = current_preview_winid()
    if winid == 0 or not vim.api.nvim_win_is_valid(winid) then
        return false
    end

    local height = vim.api.nvim_win_get_height(winid)
    local step = math.max(1, math.floor(height / 2))
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    local delta = direction == 'down' and step or -step
    local current_line = vim.api.nvim_win_get_cursor(winid)[1]
    local line = math.min(last_line, math.max(1, current_line + delta))
    vim.api.nvim_win_set_cursor(winid, { line, 0 })
    return true
end

local function preview_border()
    local border = vim.o.pumborder
    if border ~= '' then
        return border
    end
    return vim.o.winborder
end

local function preview_winhighlight()
    return 'Normal:Pmenu,FloatBorder:PmenuBorder,EndOfBuffer:Pmenu'
end

---@param winid? integer
---@return boolean styled
local function set_preview_border(winid)
    if type(winid) ~= 'number' then
        winid = nil
    end
    winid = winid
        or vim.fn.complete_info({ 'preview_winid' }).preview_winid
        or 0
    if winid == 0 or not vim.api.nvim_win_is_valid(winid) then
        return false
    end

    local border = preview_border()
    if border ~= '' and border ~= 'none' then
        vim.api.nvim_win_set_config(winid, { border = border })
    end
    vim.api.nvim_set_option_value(
        'winhl',
        preview_winhighlight(),
        { win = winid }
    )
    return true
end

vim.api.nvim_create_autocmd('CompleteChanged', {
    group = vim.api.nvim_create_augroup(
        'ACompletionPreviewBorder',
        { clear = true }
    ),
    callback = function()
        local item = vim.v.event.completed_item or {}
        local selected = vim.fn.complete_info({ 'selected' }).selected
        local info = type(item.info) == 'string' and item.info or ''
        if selected < 0 then
            return
        end
        if info ~= '' and vim.api.nvim__complete_set then
            local windata =
                vim.api.nvim__complete_set(selected, { info = info })
            set_preview_border(windata and windata.winid or nil)
            return
        end
        set_preview_border()
    end,
})

if vim.api.nvim__complete_set then
    local complete_set = vim.api.nvim__complete_set
    vim.api.nvim__complete_set = function(index, opts)
        local windata = complete_set(index, opts)
        set_preview_border(windata and windata.winid or nil)
        return windata
    end
end

---@return string keys
local function semantic_completion()
    local prefix = vim.fn.pumvisible() == 1 and '<c-e>' or ''
    if vim.bo.omnifunc ~= '' then
        return prefix .. '<c-x><c-o>'
    end
    return prefix .. '<c-n>'
end

---@param keys string
---@param direction 'up'|'down'
---@return string keys
local function completion_or_preview(keys, direction)
    set_preview_border()
    if scroll_preview(direction) then
        return ''
    end
    if vim.fn.pumvisible() == 1 then
        return ''
    end
    return keys
end

vim.keymap.set('i', '<c-b>', function()
    return completion_or_preview('<c-x><c-n>', 'up')
end, { expr = true, desc = 'buffer completion or docs backward' })
vim.keymap.set('i', '<c-e>', function()
    return vim.fn.pumvisible() == 1 and '<c-e>' or '<c-x><c-u>'
end, { expr = true, desc = 'env completion or cancel completion' })
vim.keymap.set('i', '<c-f>', function()
    set_preview_border()
    if scroll_preview('down') then
        return ''
    end
    if vim.fn.pumvisible() == 1 then
        return ''
    end
    return "<c-r>=v:lua.require'config.completion.files'.trigger()<cr>"
end, { expr = true, desc = 'fuzzy file completion or docs forward' })
vim.keymap.set('i', '<c-n>', function()
    return '<c-n>'
end, { expr = true, desc = 'next completion' })
vim.keymap.set('i', '<c-p>', function()
    return '<c-p>'
end, { expr = true, desc = 'previous completion' })
vim.keymap.set('i', '<c-s>', semantic_completion, {
    expr = true,
    desc = 'semantic completion',
})

vim.schedule(function()
    require('config.completion.files').warmup(0)
end)
