local dev_plugins = {
    'midnight.nvim',
    'live-server.nvim',
    'canola.nvim',
    'pending.nvim',
    'cp.nvim',
    'diffs.nvim',
    'preview.nvim',
    'fzf-lua',
}

local opt_dir = vim.fn.stdpath('data') .. '/site/pack/dev/opt/'
vim.fn.mkdir(opt_dir, 'p')
for _, name in ipairs(dev_plugins) do
    local link = opt_dir .. name
    if not vim.uv.fs_lstat(link) then
        vim.uv.fs_symlink(vim.fn.expand('~/dev/' .. name), link)
    end
end

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
local synctex_pdf = {}

return {
    {
        'barrettruth/diffs.nvim',
        enabled = true,
        before = function()
            vim.g.diffs = {
                debug = false,
                integrations = { fugitive = true },
                extra_filetypes = { 'diff' },
                hide_prefix = true,
                highlights = {
                    gutter = true,
                    vim = {
                        enabled = true,
                        -- max_lines = 500,
                    },
                    -- treesitter = { max_lines = 10 },
                    intra = {
                        enabled = true,
                        max_lines = 500,
                    },
                },
            }
        end,
    },
    {
        'barrettruth/midnight.nvim',
        enabled = true,
        after = function()
            vim.cmd.colorscheme('midnight')
        end,
    },
    {
        'barrettruth/live-server.nvim',
        enabled = true,
        before = function()
            vim.g.live_server = {
                debug = false,
            }
        end,
        keys = { { '<leader>l', '<cmd>LiveServerToggle<cr>' } },
    },
    {
        'barrettruth/canola.nvim',
        enabled = true,
        after = function()
            require('oil').setup({
                skip_confirm_for_simple_edits = true,
                cleanup_buffers_on_delete = true,
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
                    ['<c-h>'] = false,
                    ['<c-t>'] = false,
                    ['<c-l>'] = false,
                    ['<c-r>'] = 'actions.refresh',
                    ['<c-s>'] = { 'actions.select', opts = { vertical = true } },
                    ['<c-x>'] = {
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
                            vim.cmd('Canola ' .. path)
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
        'barrettruth/pending.nvim',
        before = function()
            vim.g.pending = {
                debug = false,
                sync = {
                    s3 = { bucket = 'pending.nvim', region = 'us-east-1' },
                },
                data_path = (
                    os.getenv('XDG_STATE_HOME')
                    or (os.getenv('HOME') .. '/.local/state')
                ) .. '/nvim/pending/tasks.json',
                date_format = '%d/%m/%y',
                date_syntax = 'd',
                recur_syntax = 'r',
                input_date_formats = { '%d/%m/%Y', '%d/%m/%y' },
                drawer_height = vim.o.lines,
            }
        end,
        cmd = 'Pending',
        keys = { { '<leader>P', '<cmd>Pending|only<cr>' } },
    },
    {
        'barrettruth/cp.nvim',
        cmd = 'CP',
        keys = {
            { '<leader>ce', '<cmd>CP edit<cr>' },
            { '<leader>cp', '<cmd>CP panel<cr>' },
            { '<leader>cP', '<cmd>CP pick<cr>' },
            { '<leader>cr', '<cmd>CP run all<cr>' },
            { '<leader>cd', '<cmd>CP run --debug<cr>' },
            { ']c', '<cmd>CP next<cr>' },
            { '[c', '<cmd>CP prev<cr>' },
        },
        before = function()
            vim.g.cp = {
                debug = false,
                templates = {
                    cursor_marker = '<++>',
                },
                languages = {
                    cpp = {
                        extension = 'cc',
                        template = '~/.config/nix/config/cp/template_multi.cc',
                        commands = {
                            build = {
                                'g++',
                                '-std=c++20',
                                '-O2',
                                '-Wall',
                                '-Wextra',
                                '-Wpedantic',
                                '-Wshadow',
                                '-Wconversion',
                                '-Wformat=2',
                                '-Wfloat-equal',
                                '-Wundef',
                                '-fdiagnostics-color=always',
                                '-DLOCAL',
                                '{source}',
                                '-o',
                                '{binary}',
                            },
                            run = { '{binary}' },
                            debug = {
                                'g++',
                                '-std=c++20',
                                '-g3',
                                '-fsanitize=address,undefined',
                                '-fno-omit-frame-pointer',
                                '-fstack-protector-all',
                                '-D_GLIBCXX_DEBUG',
                                '-DLOCAL',
                                '{source}',
                                '-o',
                                '{binary}',
                            },
                        },
                    },
                    python = {
                        extension = 'py',
                        template = '~/.config/nix/config/cp/template.py',
                        commands = {
                            run = { 'python', '{source}' },
                            debug = { 'python', '{source}' },
                        },
                    },
                },
                platforms = {
                    atcoder = {
                        overrides = {
                            cpp = {
                                template = '~/.config/nix/config/cp/template_single.cc',
                            },
                        },
                    },
                    cses = {
                        overrides = {
                            cpp = {
                                template = '~/.config/nix/config/cp/template_single.cc',
                            },
                        },
                    },
                },
                ui = {
                    picker = 'fzf-lua',
                    panel = { diff_modes = { 'side-by-side', 'git' } },
                },
                hooks = {
                    setup = {
                        contest = function(state)
                            local dir = vim.fn.fnamemodify(
                                state.get_source_file(state.get_language()),
                                ':h'
                            )
                            local path = dir .. '/.clang-format'
                            if vim.fn.filereadable(path) == 0 then
                                vim.fn.system({
                                    'cp',
                                    vim.fn.expand(
                                        '~/.config/nix/config/cp/.clang-format'
                                    ),
                                    path,
                                })
                            end
                        end,
                        code = function(_)
                            vim.opt_local.foldlevel = 0
                            vim.opt_local.foldmethod = 'marker'
                            vim.opt_local.foldmarker = '{{{,}}}'
                            vim.opt_local.foldtext = ''
                            vim.diagnostic.enable(false)
                        end,
                    },
                    on = {
                        enter = function(_)
                            vim.opt_local.winbar = ''
                        end,
                        run = function(_)
                            require('config.lsp').format()
                        end,
                        debug = function(_)
                            require('config.lsp').format()
                        end,
                    },
                },
                filename = function(_, _, problem_id)
                    return problem_id
                end,
            }
        end,
        after = function()
            vim.cmd.packadd('fzf-lua')
        end,
    },
    {
        'barrettruth/preview.nvim',
        ft = { 'typst', 'tex', 'markdown', 'plantuml' },
        before = function()
            vim.filetype.add({
                extension = { puml = 'plantuml', pu = 'plantuml' },
            })

            vim.api.nvim_create_autocmd('User', {
                pattern = 'PreviewCompileSuccess',
                callback = function(args)
                    synctex_pdf[args.data.bufnr] = args.data.output
                end,
            })
            vim.api.nvim_create_autocmd('CursorHold', {
                group = vim.api.nvim_create_augroup(
                    'APreviewSynctex',
                    { clear = true }
                ),
                pattern = '*.tex',
                callback = function()
                    local pdf = synctex_pdf[vim.api.nvim_get_current_buf()]
                    if pdf then
                        vim.fn.jobstart({
                            'sioyek',
                            '--instance-name',
                            'preview',
                            '--reuse-window',
                            '--forward-search-file',
                            vim.fn.expand('%:p'),
                            '--forward-search-line',
                            tostring(vim.fn.line('.')),
                            pdf,
                        })
                    end
                end,
            })
            vim.g.preview = {
                debug = false,
                github = {
                    output = function(ctx)
                        return '/tmp/'
                            .. vim.fn.fnamemodify(ctx.file, ':t:r')
                            .. '.html'
                    end,
                },
                typst = { open = { 'sioyek', '--new-instance' } },
                plantuml = true,
                mermaid = true,
                latex = {
                    open = { 'sioyek', '--instance-name', 'preview' },
                    output = function(ctx)
                        return vim.fn.fnamemodify(ctx.file, ':h')
                            .. '/build/'
                            .. vim.fn.fnamemodify(ctx.file, ':t:r')
                            .. '.pdf'
                    end,
                },
            }
        end,
        keys = {
            { '<leader>p', '<cmd>Preview toggle<cr>' },
        },
    },
}
