vim.pack.add({
    'https://github.com/nvim-treesitter/nvim-treesitter',
    'https://github.com/nvim-treesitter/nvim-treesitter-textobjects',
    'https://github.com/Wansmer/treesj',
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
                    map({
                        m,
                        t[1],
                        function()
                            select.select_textobject(t[2], 'textobjects', m)
                        end,
                    })
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
                    map({
                        m,
                        ']' .. key,
                        function()
                            move.goto_next_start(capture, 'textobjects')
                        end,
                    })
                    map({
                        m,
                        '[' .. key,
                        function()
                            move.goto_previous_start(capture, 'textobjects')
                        end,
                    })
                    local upper = key:upper()
                    if upper ~= key then
                        map({
                            m,
                            ']' .. upper,
                            function()
                                move.goto_next_end(capture, 'textobjects')
                            end,
                        })
                        map({
                            m,
                            '[' .. upper,
                            function()
                                move.goto_previous_end(capture, 'textobjects')
                            end,
                        })
                    end
                end
            end

            local ts_repeat =
                require('nvim-treesitter-textobjects.repeatable_move')
            for _, m in ipairs({ 'n', 'x', 'o' }) do
                map({ m, ';', ts_repeat.repeat_last_move_next })
                map({ m, ',', ts_repeat.repeat_last_move_previous })
                map({ m, 'f', ts_repeat.builtin_f_expr }, { expr = true })
                map({ m, 'F', ts_repeat.builtin_F_expr }, { expr = true })
                map({ m, 't', ts_repeat.builtin_t_expr }, { expr = true })
                map({ m, 'T', ts_repeat.builtin_T_expr }, { expr = true })
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
