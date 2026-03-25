vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
})

-- selene: allow(global_usage)
function _G._fugitive_stl()
    local s = vim.fn.FugitiveStatusline()
    return s ~= '' and s .. ' ' or ''
end

vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        vim.o.statusline = ' %{v:lua._fugitive_stl()}'
            .. vim.o.statusline:sub(2)
    end,
})

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    callback = function()
        vim.fn.matchadd('DiffAdd', [[\v\+\d+]])
        vim.fn.matchadd('DiffDelete', [[\v-\d+]])
        vim.fn.matchadd('DiffChange', [[\v\s\zsM\ze\s]])
        vim.fn.matchadd('diffAdded', [[\v\s\zsA\ze\s]])
        vim.fn.matchadd('DiffDelete', [[\v\s\zsD\ze\s]])
        vim.fn.matchadd('DiffText', [[\v\s\zsR\ze\s]])
    end,
})

local function close_review_view()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('^fugitive://') or name:match('^diffs://review:') then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    pcall(vim.cmd, 'diffoff!')
end

vim.keymap.set('n', ']q', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.cnext) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', '[q', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.cprev) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', ']g', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.lnext) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', '[g', function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
        close_review_view()
    end
    if not pcall(vim.cmd.lprev) then
        return
    end
    if review.base and review.mode == 'split' then
        pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
end)

vim.keymap.set('n', 's', function()
    local review = require('forge').review
    if not review.base then
        vim.cmd('normal! s')
        return
    end
    if review.mode == 'unified' then
        local commands = require('diffs.commands')
        local file = commands.review_file_at_line(
            vim.api.nvim_get_current_buf(),
            vim.fn.line('.')
        )
        review.mode = 'split'
        if file then
            vim.cmd('edit ' .. vim.fn.fnameescape(file))
            pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
        end
    else
        local current_file = vim.fn.expand('%:.')
        close_review_view()
        review.mode = 'unified'
        require('diffs.commands').greview(review.base)
        if current_file ~= '' then
            vim.fn.search(
                'diff %-%-git a/' .. vim.pesc(current_file),
                'cw'
            )
        end
    end
end)
