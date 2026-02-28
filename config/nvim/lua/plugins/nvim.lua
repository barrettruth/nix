local function parse_output(proc)
    local result = proc:wait()
    local ret = {}
    if result.code == 0 then
        for line in
            vim.gsplit(result.stdout, '\n', { plain = true, trimempty = true })
        do
            ret[line:gsub('/$', '')] = true
        end
    end
    return ret
end

local function new_git_status()
    return setmetatable({}, {
        __index = function(self, key)
            local ignored_proc = vim.system({
                'git',
                'ls-files',
                '--ignored',
                '--exclude-standard',
                '--others',
                '--directory',
            }, { cwd = key, text = true })
            local tracked_proc = vim.system(
                { 'git', 'ls-tree', 'HEAD', '--name-only' },
                { cwd = key, text = true }
            )
            local ret = {
                ignored = parse_output(ignored_proc),
                tracked = parse_output(tracked_proc),
            }
            rawset(self, key, ret)
            return ret
        end,
    })
end

local git_status = new_git_status()

vim.pack.add({
    -- 'https://github.com/barrettruth/midnight.nvim',
    'https://github.com/echasnovski/mini.ai',
    'https://github.com/monaqa/dial.nvim',
    'https://github.com/catgoose/nvim-colorizer.lua',
    'https://github.com/echasnovski/mini.pairs',
    'https://github.com/echasnovski/mini.misc',
    'https://github.com/nvim-mini/mini.bufremove',
    'https://github.com/tpope/vim-abolish',
    'https://github.com/tpope/vim-sleuth',
    'https://github.com/kylechui/nvim-surround',
    'https://github.com/lervag/vimtex',
})

return {
    {
        'barrettruth/live-server.nvim',
        enabled = false,
        before = function()
            vim.g.live_server = {
                debug = false,
            }
        end,
        keys = { { '<leader>l', '<cmd>LiveServerToggle<cr>' } },
    },
    {
        'barrettruth/midnight.nvim',
        after = function()
            vim.cmd.colorscheme('midnight')
        end,
    },
    {
        'barrettruth/nonicons.nvim',
        enabled = false,
    },
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
        'barrettruth/canola.nvim',
        enabled = true,
        after = function()
            require('oil').setup({
                skip_confirm_for_simple_edits = true,
                prompt_save_on_select_new_entry = false,
                float = { border = 'single' },
                view_options = {
                    is_hidden_file = function(name, bufnr)
                        local dir = require('oil').get_current_dir(bufnr)
                        local is_dotfile = vim.startswith(name, '.')
                            and name ~= '..'
                        if not dir then
                            return is_dotfile
                        end
                        if is_dotfile then
                            return not git_status[dir].tracked[name]
                        else
                            return git_status[dir].ignored[name]
                        end
                    end,
                },
                keymaps = {
                    ['<C-h>'] = false,
                    ['<C-t>'] = false,
                    ['<C-l>'] = false,
                    ['<C-r>'] = 'actions.refresh',
                    ['<C-s>'] = { 'actions.select', opts = { vertical = true } },
                    ['<C-x>'] = {
                        'actions.select',
                        opts = { horizontal = true },
                    },
                    q = function()
                        local ok, bufremove = pcall(require, 'mini.bufremove')
                        if ok then
                            bufremove.delete()
                        else
                            vim.cmd.bd()
                        end
                    end,
                },
            })
            local refresh = require('oil.actions').refresh
            local orig_refresh = refresh.callback
            refresh.callback = function(...)
                git_status = new_git_status()
                orig_refresh(...)
            end
            vim.api.nvim_create_autocmd('BufEnter', {
                callback = function()
                    local ft = vim.bo.filetype
                    if ft == '' then
                        local path = vim.fn.expand('%:p')
                        if vim.fn.isdirectory(path) == 1 then
                            vim.cmd('Oil ' .. path)
                        end
                    end
                end,
                group = vim.api.nvim_create_augroup('AOil', { clear = true }),
            })
        end,
        event = 'DeferredUIEnter',
        keys = {
            { '-', '<cmd>e .<cr>' },
            { '_', '<cmd>Oil<cr>' },
        },
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
    {
        -- TODO: replace this with own barrettruth/render.nvim
        'wallpants/github-preview.nvim',
        after = function()
            require('github-preview').setup({
                single_file = true,
                cursor_line = {
                    disable = true,
                },
            })
        end,
        keys = { { '<leader>m', '<cmd>silent GithubPreviewToggle<cr>' } },
    },
    {
        'barrettruth/pending.nvim',
        before = function()
            vim.g.pending = { debug = true }
        end,
        -- TODO: should we be using this or `<Plug>` mappings?
        keys = { { '<leader>p', '<cmd>Pending<cr>' } },
    },
}
