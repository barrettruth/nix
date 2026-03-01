vim.pack.add({
    { src = 'https://github.com/echasnovski/mini.ai', load = false },
    { src = 'https://github.com/monaqa/dial.nvim', load = false },
    { src = 'https://github.com/catgoose/nvim-colorizer.lua', load = false },
    { src = 'https://github.com/echasnovski/mini.pairs', load = false },
    { src = 'https://github.com/echasnovski/mini.misc', load = false },
    { src = 'https://github.com/nvim-mini/mini.bufremove', load = false },
    { src = 'https://github.com/tpope/vim-abolish', load = false },
    { src = 'https://github.com/tpope/vim-sleuth', load = false },
    { src = 'https://github.com/kylechui/nvim-surround', load = false },
    { src = 'https://github.com/lervag/vimtex', load = false },
})

return {
    {
        'echasnovski/mini.pairs',
        after = function()
            require('mini.pairs').setup()
        end,
        event = 'InsertEnter',
    },
    {
        'echasnovski/mini.ai',
        after = function()
            require('mini.ai').setup({
                custom_textobjects = {
                    b = false,
                    f = false,
                    e = function(ai_type)
                        local n_lines = vim.fn.line('$')
                        local start_line, end_line = 1, n_lines
                        if ai_type == 'i' then
                            while
                                start_line <= n_lines
                                and vim.fn.getline(start_line):match('^%s*$')
                            do
                                start_line = start_line + 1
                            end
                            while
                                end_line >= start_line
                                and vim.fn.getline(end_line):match('^%s*$')
                            do
                                end_line = end_line - 1
                            end
                        end
                        local to_col =
                            math.max(vim.fn.getline(end_line):len(), 1)
                        return {
                            from = { line = start_line, col = 1 },
                            to = { line = end_line, col = to_col },
                        }
                    end,
                    l = function(ai_type)
                        local line_num = vim.fn.line('.')
                        local line = vim.fn.getline(line_num)
                        if line == '' then
                            return {
                                from = { line = line_num, col = 1 },
                                to = { line = line_num, col = 1 },
                            }
                        end
                        local start_col, end_col
                        if ai_type == 'i' then
                            start_col = line:find('%S') or 1
                            end_col = line:match('.*%S()') or 1
                        else
                            start_col, end_col = 1, line:len()
                        end
                        return {
                            from = { line = line_num, col = start_col },
                            to = { line = line_num, col = end_col },
                        }
                    end,
                    I = function(ai_type)
                        local cur_line = vim.fn.line('.')
                        local cur_indent = vim.fn.indent(cur_line)
                        if vim.fn.getline(cur_line):match('^%s*$') then
                            local search_line = cur_line + 1
                            while
                                search_line <= vim.fn.line('$')
                                and vim.fn.getline(search_line):match('^%s*$')
                            do
                                search_line = search_line + 1
                            end
                            if search_line <= vim.fn.line('$') then
                                cur_indent = vim.fn.indent(search_line)
                            end
                        end
                        local start_line, end_line = cur_line, cur_line
                        while start_line > 1 do
                            local prev = start_line - 1
                            local prev_blank =
                                vim.fn.getline(prev):match('^%s*$')
                            if ai_type == 'i' and prev_blank then
                                break
                            end
                            if
                                not prev_blank
                                and vim.fn.indent(prev) < cur_indent
                            then
                                break
                            end
                            start_line = prev
                        end
                        while end_line < vim.fn.line('$') do
                            local next = end_line + 1
                            local next_blank =
                                vim.fn.getline(next):match('^%s*$')
                            if ai_type == 'i' and next_blank then
                                break
                            end
                            if
                                not next_blank
                                and vim.fn.indent(next) < cur_indent
                            then
                                break
                            end
                            end_line = next
                        end
                        local to_col =
                            math.max(vim.fn.getline(end_line):len(), 1)
                        return {
                            from = { line = start_line, col = 1 },
                            to = { line = end_line, col = to_col },
                        }
                    end,
                },
            })
        end,
        keys = {
            { 'a', mode = { 'x', 'o' } },
            { 'i', mode = { 'x', 'o' } },
        },
    },
    {
        'lervag/vimtex',
        ft = { 'latex' },
        before = function()
            vim.g.vimtex_view_method = 'sioyek'
            vim.g.vimtex_quickfix_mode = 0
        end,
    },
    {
        'monaqa/dial.nvim',
        after = function()
            local augend = require('dial.augend')
            require('dial.config').augends:register_group({
                default = {
                    augend.integer.alias.decimal_int,
                    augend.integer.alias.hex,
                    augend.integer.alias.octal,
                    augend.integer.alias.binary,
                    augend.constant.alias.bool,
                    augend.constant.alias.alpha,
                    augend.constant.alias.Alpha,
                    augend.semver.alias.semver,
                },
            })
        end,
        keys = {
            {
                '<c-a>',
                function()
                    require('dial.map').manipulate('increment', 'normal')
                end,
                mode = 'n',
            },
            {
                '<c-x>',
                function()
                    require('dial.map').manipulate('decrement', 'normal')
                end,
                mode = 'n',
            },
            {
                'g<c-a>',
                function()
                    require('dial.map').manipulate('increment', 'gnormal')
                end,
                mode = 'n',
            },
            {
                'g<c-x>',
                function()
                    require('dial.map').manipulate('decrement', 'gnormal')
                end,
                mode = 'n',
            },
            {
                '<c-a>',
                function()
                    require('dial.map').manipulate('increment', 'visual')
                end,
                mode = 'v',
            },
            {
                '<c-x>',
                function()
                    require('dial.map').manipulate('decrement', 'visual')
                end,
                mode = 'v',
            },
            {
                'g<c-a>',
                function()
                    require('dial.map').manipulate('increment', 'gvisual')
                end,
                mode = 'v',
            },
            {
                'g<c-x>',
                function()
                    require('dial.map').manipulate('decrement', 'gvisual')
                end,
                mode = 'v',
            },
        },
    },
    {
        'catgoose/nvim-colorizer.lua',
        after = function()
            require('colorizer').setup({
                user_default_options = {
                    names = false,
                    rrggbbaa = true,
                    css = true,
                    css_fn = true,
                    rgb_fn = true,
                    hsl_fn = true,
                },
            })
        end,
        event = 'BufReadPre',
    },
    {
        'echasnovski/mini.misc',
        after = function()
            require('mini.misc').setup()
        end,
        keys = {
            {
                '<c-w>m',
                "<cmd>lua MiniMisc.zoom(0, { title = '', border = 'none' })<cr>",
            },
        },
    },
    {
        'nvim-mini/mini.bufremove',
        after = function()
            require('mini.bufremove').setup()
        end,
        keys = {
            {
                '<leader>bd',
                '<cmd>lua MiniBufremove.delete()<cr>',
            },
            {
                '<leader>bw',
                '<cmd>lua MiniBufremove.wipeout()<cr>',
            },
        },
    },
    { 'tpope/vim-abolish', event = 'DeferredUIEnter' },
    { 'tpope/vim-sleuth', event = 'BufReadPost' },
    {
        'kylechui/nvim-surround',
        after = function()
            require('nvim-surround').setup()
        end,
        keys = {
            { 'cs', mode = 'n' },
            { 'ds', mode = 'n' },
            { 'ys', mode = 'n' },
            { 'yS', mode = 'n' },
            { 'yss', mode = 'n' },
            { 'ySs', mode = 'n' },
        },
    },
}
