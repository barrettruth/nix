vim.pack.add({
    'https://github.com/nvim-treesitter/nvim-treesitter',
    'https://github.com/nvim-treesitter/nvim-treesitter-textobjects',
    { src = 'https://github.com/Wansmer/treesj', load = false },
})

vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
        local name, kind = ev.data.spec.name, ev.data.kind
        if kind == 'delete' then
            return
        end
        if name == 'nvim-treesitter' then
            vim.schedule(function()
                vim.cmd('TSUpdate all')
            end)
        end
    end,
})

return {
    {
        'nvim-treesitter/nvim-treesitter',
        after = function()
            require('nvim-treesitter').setup({ auto_install = true })
        end,
    },
    {
        'nvim-treesitter/nvim-treesitter-textobjects',
        before = function()
            vim.g.no_plugin_maps = true
        end,
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
                    end)
                end
            end

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
                    end)
                    vim.keymap.set(m, '[' .. key, function()
                        move.goto_previous_start(capture, 'textobjects')
                    end)
                    local upper = key:upper()
                    if upper ~= key then
                        vim.keymap.set(m, ']' .. upper, function()
                            move.goto_next_end(capture, 'textobjects')
                        end)
                        vim.keymap.set(m, '[' .. upper, function()
                            move.goto_previous_end(capture, 'textobjects')
                        end)
                    end
                end
            end

            local ts_repeat =
                require('nvim-treesitter-textobjects.repeatable_move')
            for _, m in ipairs({ 'n', 'x', 'o' }) do
                vim.keymap.set(m, ';', ts_repeat.repeat_last_move_next)
                vim.keymap.set(m, ',', ts_repeat.repeat_last_move_previous)
                vim.keymap.set(
                    m,
                    'f',
                    ts_repeat.builtin_f_expr,
                    { expr = true }
                )
                vim.keymap.set(
                    m,
                    'F',
                    ts_repeat.builtin_F_expr,
                    { expr = true }
                )
                vim.keymap.set(
                    m,
                    't',
                    ts_repeat.builtin_t_expr,
                    { expr = true }
                )
                vim.keymap.set(
                    m,
                    'T',
                    ts_repeat.builtin_T_expr,
                    { expr = true }
                )
            end
        end,
    },
    {
        'Wansmer/treesj',
        after = function()
            require('treesj').setup()
        end,
        keys = {
            { 'gt', '<cmd>lua require("treesj").toggle()<cr>' },
        },
    },
}
