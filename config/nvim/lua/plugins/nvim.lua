local oil_detail = false

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

return {
    {
        'barrettruth/live-server.nvim',
        enabled = false,
        init = function()
            vim.g.live_server = {
                debug = false
            }
        end,
        keys = { { '<leader>l', '<cmd>LiveServerToggle<cr>' } },
    },
    {
        'barrettruth/midnight.nvim',
        config = function()
            vim.cmd.colorscheme('midnight')
        end,
    },
    {
        'barrettruth/nonicons.nvim',
        dir = '~/dev/nonicons.nvim',
        enabled = true,
        lazy = false,
        dependencies = {
            'nvim-tree/nvim-web-devicons',
        },
    },
    {
        'echasnovski/mini.pairs',
        config = true,
        event = 'InsertEnter',
    },
    {
        'echasnovski/mini.ai',
        opts = {
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
                    local to_col = math.max(vim.fn.getline(end_line):len(), 1)
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
                        local prev_blank = vim.fn.getline(prev):match('^%s*$')
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
                        local next_blank = vim.fn.getline(next):match('^%s*$')
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
                    local to_col = math.max(vim.fn.getline(end_line):len(), 1)
                    return {
                        from = { line = start_line, col = 1 },
                        to = { line = end_line, col = to_col },
                    }
                end,
            },
        },
        keys = {
            { 'a', mode = { 'x', 'o' } },
            { 'i', mode = { 'x', 'o' } },
        },
    },
    {
        'lervag/vimtex',
        ft = { 'latex' },
        init = function()
            vim.g.vimtex_view_method = 'sioyek'
            vim.g.vimtex_quickfix_mode = 0
        end,
    },
    {
        'monaqa/dial.nvim',
        config = function(_)
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
        opts = {
            user_default_options = {
                names = false,
                rrggbbaa = true,
                css = true,
                css_fn = true,
                rgb_fn = true,
                hsl_fn = true,
            },
        },
        event = 'BufReadPre',
    },
    {
        'barrettruth/canola.nvim',
        dir = '~/dev/canola.nvim',
        config = function(_, opts)
            require('oil').setup(opts)
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
        event = 'VeryLazy',
        keys = {
            { '-', '<cmd>e .<cr>' },
            { '_', vim.cmd.Oil },
        },
        opts = {
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
                ['<C-x>'] = { 'actions.select', opts = { horizontal = true } },
                q = function()
                    local ok, bufremove = pcall(require, 'mini.bufremove')
                    if ok then
                        bufremove.delete()
                    else
                        vim.cmd.bd()
                    end
                end,
            },
        },
        dependencies = {
            {
                'malewicz1337/oil-git.nvim',
                dir = '~/dev/oil-git.nvim',
                opts = {
                    symbol_position = 'signcolumn',
                    can_use_signcolumn = function()
                        return true
                    end,
                    show_file_highlights = false,
                    show_directory_highlights = false,
                    symbols = {
                        file = {
                            added = '│',
                            modified = '│',
                            renamed = '│',
                            deleted = '＿',
                            copied = '│',
                            conflict = '│',
                            untracked = '│',
                            ignored = ' ',
                        },
                        directory = {
                            added = '│',
                            modified = '│',
                            renamed = '│',
                            deleted = '＿',
                            copied = '│',
                            conflict = '│',
                            untracked = '│',
                            ignored = ' ',
                        },
                    },
                    highlights = {
                        OilGitAdded = { link = 'GitSignsAdd' },
                        OilGitModified = { link = 'GitSignsChange' },
                        OilGitRenamed = { link = 'GitSignsChange' },
                        OilGitDeleted = { link = 'GitSignsDelete' },
                        OilGitCopied = { link = 'GitSignsChange' },
                        OilGitConflict = { link = 'GitSignsDelete' },
                        OilGitUntracked = { link = 'GitSignsAdd' },
                        OilGitIgnored = { link = 'Comment' },
                    },
                },
            },
        },
    },
    {
        'echasnovski/mini.misc',
        config = true,
        keys = {
            {
                '<c-w>m',
                "<cmd>lua MiniMisc.zoom(0, { title = '', border = 'none' })<cr>",
            },
        },
    },
    {
        'nvim-mini/mini.bufremove',
        config = true,
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
    { 'tpope/vim-abolish', event = 'VeryLazy' },
    { 'tpope/vim-sleuth', event = 'BufReadPost' },
    {
        'kylechui/nvim-surround',
        config = true,
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
        dir = '~/dev/github-preview.nvim',
        keys = { { '<leader>m', '<cmd>silent GithubPreviewToggle<cr>' } },
        opts = {
            single_file = true,
            cursor_line = {
                disable = true,
            },
        },
    },
    {
        'barrettruth/pending.nvim'
    }
}
