vim.pack.add({
    'https://github.com/echasnovski/mini.ai',
    'https://github.com/echasnovski/mini.bracketed',
    'https://github.com/nvim-mini/mini.completion',
    'https://github.com/monaqa/dial.nvim',
    'https://github.com/catgoose/nvim-colorizer.lua',
    'https://github.com/echasnovski/mini.pairs',
    'https://github.com/tpope/vim-abolish',
    'https://github.com/tpope/vim-apathy',
    'https://github.com/tpope/vim-characterize',
    'https://github.com/tpope/vim-repeat',
    'https://github.com/tpope/vim-sleuth',
    'https://github.com/kylechui/nvim-surround',
}, { load = function() end })

return {
    {
        'echasnovski/mini.pairs',
        after = function()
            require('mini.pairs').setup()
        end,
        event = 'InsertEnter',
    },
    {
        'nvim-mini/mini.completion',
        after = function()
            local completion = require('mini.completion')
            completion.setup({
                delay = { completion = 10000000, info = 100, signature = 50 },
                lsp_completion = {
                    source_func = 'omnifunc',
                    auto_setup = false,
                },
                mappings = {
                    force_twostep = '',
                    force_fallback = '',
                    scroll_down = '<c-f>',
                    scroll_up = '<c-b>',
                },
            })

            local function set_omnifunc(bufnr)
                if not vim.api.nvim_buf_is_valid(bufnr) then
                    return
                end
                for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    if client:supports_method('textDocument/completion') then
                        vim.bo[bufnr].omnifunc =
                            'v:lua.MiniCompletion.completefunc_lsp'
                        return
                    end
                end
            end

            vim.api.nvim_create_autocmd('LspAttach', {
                group = vim.api.nvim_create_augroup(
                    'AMiniCompletionLsp',
                    { clear = true }
                ),
                callback = function(ev)
                    set_omnifunc(ev.buf)
                end,
            })

            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(bufnr) then
                    set_omnifunc(bufnr)
                end
            end

            local function pumvisible()
                return vim.fn.pumvisible() == 1
            end

            vim.keymap.set('i', '<c-n>', function()
                if pumvisible() then
                    return '<c-n>'
                end
                completion.complete_twostage()
                return ''
            end, { expr = true, desc = 'complete next' })
            vim.keymap.set('i', '<c-p>', function()
                return pumvisible() and '<c-p>' or ''
            end, { expr = true, desc = 'complete previous' })
            vim.keymap.set('i', '<c-t>', '<c-x><c-f>', {
                desc = 'file completion',
            })
            vim.keymap.set('i', '<c-;>', '<c-x><c-v>', {
                desc = 'vim command completion',
            })
            vim.keymap.set('i', '<c-r>', '<c-x><c-r>', {
                desc = 'register completion',
            })
        end,
        event = 'InsertEnter',
    },
    {
        'echasnovski/mini.ai',
        keys = {
            { 'a', mode = { 'x', 'o' } },
            { 'i', mode = { 'x', 'o' } },
        },
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

            vim.api.nvim_create_autocmd('BufWinEnter', {
                group = vim.api.nvim_create_augroup('colorizer-generated', {}),
                pattern = { 'forge://*', 'ci://*' },
                callback = function(ev)
                    vim.schedule(function()
                        pcall(require('colorizer').detach_from_buffer, ev.buf)
                    end)
                end,
            })
        end,
        event = 'BufReadPre',
    },
    { 'tpope/vim-abolish', event = 'DeferredUIEnter' },
    { 'tpope/vim-apathy' },
    { 'tpope/vim-characterize' },
    { 'tpope/vim-repeat' },
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
    {
        'echasnovski/mini.bracketed',
        after = function()
            require('mini.bracketed').setup({
                comment = { suffix = '' },
                conflict = { suffix = '' },
                diagnostic = { suffix = '' },
                file = { suffix = '' },
                indent = { suffix = '' },
                treesitter = { suffix = '' },
                undo = { suffix = '' },
            })
        end,
        event = 'DeferredUIEnter',
    },
}
