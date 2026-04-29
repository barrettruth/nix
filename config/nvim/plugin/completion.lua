vim.opt.complete = { '.', 'w', 'b', 'o' }
vim.o.completefunc = "v:lua.require'config.completion'.complete"
vim.opt.completeopt = { 'menuone', 'noinsert', 'popup' }

vim.o.autocomplete = false
vim.o.pumborder = 'single'
vim.o.pumheight = 15
vim.o.pumwidth = 24
vim.o.pummaxwidth = 80

local function preview_winid()
    local info = vim.fn.complete_info({ 'preview_winid' })
    local winid = info.preview_winid or 0
    return type(winid) == 'number' and winid or 0
end

local function scroll_preview(direction)
    local winid = preview_winid()
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

local function set_preview_border()
    local border = preview_border()
    if border == '' or border == 'none' then
        return false
    end

    local winid = preview_winid()
    if winid == 0 or not vim.api.nvim_win_is_valid(winid) then
        return false
    end

    vim.api.nvim_win_set_config(winid, { border = border })
    return true
end

if not vim.g.completion_preview_border_wrapped then
    local native_complete_set = vim.api.nvim__complete_set
    vim.api.nvim__complete_set = function(index, opts)
        local windata = native_complete_set(index, opts)
        local border = preview_border()
        local winid = type(windata) == 'table' and windata.winid or 0
        if
            border ~= ''
            and border ~= 'none'
            and type(winid) == 'number'
            and winid ~= 0
            and vim.api.nvim_win_is_valid(winid)
        then
            vim.api.nvim_win_set_config(winid, { border = border })
        end
        return windata
    end
    vim.g.completion_preview_border_wrapped = true
end

local function semantic_completion()
    local prefix = vim.fn.pumvisible() == 1 and '<C-e>' or ''
    if vim.bo.omnifunc ~= '' then
        return prefix .. '<C-x><C-o>'
    end
    return prefix .. '<C-n>'
end

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
    return completion_or_preview('<C-x><C-n>', 'up')
end, { expr = true, desc = 'buffer completion or docs backward' })
vim.keymap.set('i', '<c-e>', function()
    return vim.fn.pumvisible() == 1 and '<C-e>' or '<C-x><C-u>'
end, { expr = true, desc = 'env completion or cancel completion' })
vim.keymap.set('i', '<c-f>', function()
    return completion_or_preview('<C-x><C-f>', 'down')
end, { expr = true, desc = 'file completion or docs forward' })
vim.keymap.set('i', '<c-n>', function()
    return '<C-n>'
end, { expr = true, desc = 'next completion' })
vim.keymap.set('i', '<c-p>', function()
    return '<C-p>'
end, { expr = true, desc = 'previous completion' })
vim.keymap.set('i', '<c-s>', semantic_completion, {
    expr = true,
    desc = 'semantic completion',
})
