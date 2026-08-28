vim.pack.add({
    'https://github.com/nvim-treesitter/nvim-treesitter-textobjects',
})

vim.treesitter.language.register('starlark', 'bzl')

local group = vim.api.nvim_create_augroup('ATreesitter', { clear = true })

---@param buf integer
---@param lang string
local function start(buf, lang)
    if
        vim.api.nvim_buf_is_loaded(buf)
        and vim.treesitter.language.get_lang(vim.bo[buf].filetype) == lang
        and not vim.treesitter.highlighter.active[buf]
    then
        pcall(vim.treesitter.start, buf, lang)
    end
end

vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(ev)
        local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
        if lang and vim.treesitter.language.add(lang) then
            start(ev.buf, lang)
        end
    end,
})

return {
    {
        'nvim-treesitter/nvim-treesitter-textobjects',
        after = function()
            require('nvim-treesitter-textobjects').setup({
                select = {
                    enable = true,
                    lookahead = true,
                },
                move = {
                    enable = true,
                    set_jumps = true,
                },
            })

            local select = require('nvim-treesitter-textobjects.select')
            local select_maps = {
                { 'aa', '@parameter.outer' },
                { 'ia', '@parameter.inner' },
                { 'as', '@class.outer' },
                { 'is', '@class.inner' },
                { 'aC', '@call.outer' },
                { 'iC', '@call.inner' },
                { 'af', '@function.outer' },
                { 'if', '@function.inner' },
                { 'ai', '@conditional.outer' },
                { 'ii', '@conditional.inner' },
                { 'aL', '@loop.outer' },
                { 'iL', '@loop.inner' },
            }
            for _, m in ipairs({ 'x', 'o' }) do
                for _, t in ipairs(select_maps) do
                    vim.keymap.set(m, t[1], function()
                        select.select_textobject(t[2], 'textobjects', m)
                    end, { desc = 'select ' .. t[2] })
                end
            end

            local incremental_select = require('vim.treesitter._select')
            vim.keymap.set('x', '+', function()
                if vim.treesitter.get_parser(nil, nil, { error = false }) then
                    incremental_select.select_parent(vim.v.count1)
                else
                    vim.lsp.buf.selection_range(vim.v.count1)
                end
            end, { desc = 'expand selection' })
            vim.keymap.set('x', '-', function()
                if vim.treesitter.get_parser(nil, nil, { error = false }) then
                    incremental_select.select_child(vim.v.count1)
                else
                    vim.lsp.buf.selection_range(-vim.v.count1)
                end
            end, { desc = 'shrink selection' })

            local move = require('nvim-treesitter-textobjects.move')
            local move_textobjects = {
                { 'a', '@parameter.inner' },
                { 's', '@class.outer' },
                { 'f', '@function.outer' },
                { 'i', '@conditional.outer' },
                { '/', '@comment.outer' },
            }
            for _, m in ipairs({ 'n', 'x', 'o' }) do
                for _, t in ipairs(move_textobjects) do
                    local key, capture = t[1], t[2]
                    vim.keymap.set(m, ']' .. key, function()
                        move.goto_next_start(capture, 'textobjects')
                    end, {
                        desc = 'next ' .. capture .. ' start',
                    })
                    vim.keymap.set(m, '[' .. key, function()
                        move.goto_previous_start(capture, 'textobjects')
                    end, {
                        desc = 'prev ' .. capture .. ' start',
                    })
                    local upper = key:upper()
                    if upper ~= key then
                        vim.keymap.set(m, ']' .. upper, function()
                            move.goto_next_end(capture, 'textobjects')
                        end, {
                            desc = 'next ' .. capture .. ' end',
                        })
                        vim.keymap.set(m, '[' .. upper, function()
                            move.goto_previous_end(capture, 'textobjects')
                        end, {
                            desc = 'prev ' .. capture .. ' end',
                        })
                    end
                end
            end

            local ts_repeat =
                require('nvim-treesitter-textobjects.repeatable_move')
            for _, m in ipairs({ 'n', 'x', 'o' }) do
                vim.keymap.set(
                    m,
                    ';',
                    ts_repeat.repeat_last_move_next,
                    { desc = 'repeat last move next' }
                )
                vim.keymap.set(
                    m,
                    ',',
                    ts_repeat.repeat_last_move_previous,
                    { desc = 'repeat last move prev' }
                )
                vim.keymap.set(
                    m,
                    'f',
                    ts_repeat.builtin_f_expr,
                    { expr = true, desc = 'repeatable f' }
                )
                vim.keymap.set(
                    m,
                    'F',
                    ts_repeat.builtin_F_expr,
                    { expr = true, desc = 'repeatable F' }
                )
                vim.keymap.set(
                    m,
                    't',
                    ts_repeat.builtin_t_expr,
                    { expr = true, desc = 'repeatable t' }
                )
                vim.keymap.set(
                    m,
                    'T',
                    ts_repeat.builtin_T_expr,
                    { expr = true, desc = 'repeatable T' }
                )
            end
        end,
    },
}
