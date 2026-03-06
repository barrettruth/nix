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
            require('canola').setup({
                skip_confirm_for_simple_edits = true,
                prompt_save_on_select_new_entry = false,
                float = { border = 'single' },
                view_options = {
                    is_hidden_file = function(name, bufnr)
                        local dir = require('canola').get_current_dir(bufnr)
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
            -- TODO: better way to do this allowing vim.g.canola as that's it
            local refresh = require('canola.actions').refresh
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
                group = vim.api.nvim_create_augroup('ACanola', { clear = true }),
            })
        end,
        event = 'DeferredUIEnter',
        keys = {
            { '-', '<cmd>e .<cr>' },
            { '_', '<cmd>Canola<cr>' },
        },
    },
    {
        'barrettruth/pending.nvim',
        before = function()
            vim.g.pending = { debug = true }
        end,
        cmd = 'Pending',
        keys = { { '<leader>P', '<cmd>Pending<cr>' } },
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
                                '-std=c++23',
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
                                '-std=c++23',
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
                    codeforces = {
                        enabled_languages = { 'cpp', 'python' },
                        default_language = 'cpp',
                    },
                    atcoder = {
                        enabled_languages = { 'cpp', 'python' },
                        default_language = 'cpp',
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
            vim.g.preview = {
                github = true,
                typst = { open = { 'sioyek', '--new-instance' } },
                plantuml = true,
                mermaid = true,
                latex = {
                    open = {
                        'sioyek',
                        '--instance-name', 'preview',
                    },
                    output = function(ctx)
                        return vim.fn.fnamemodify(ctx.file, ':h')
                            .. '/build/'
                            .. vim.fn.fnamemodify(ctx.file, ':t:r')
                            .. '.pdf'
                    end,
                    args = function(ctx)
                        return {
                            '-pdf',
                            '-interaction=nonstopmode',
                            '-synctex=1',
                            '-outdir=build',
                            '-pdflatex=pdflatex -file-line-error -interaction=nonstopmode %O %S',
                            ctx.file,
                        }
                    end,
                },
            }
        end,
        keys = {
            { '<leader>p', '<cmd>Preview toggle<cr>' },
            {
                '<leader>s',
                function()
                    local bufnr = vim.api.nvim_get_current_buf()
                    local pdf = synctex_pdf[bufnr]
                    if pdf then
                        vim.fn.jobstart({
                            'sioyek',
                            '--instance-name', 'preview',
                            '--forward-search-file', vim.fn.expand('%:p'),
                            '--forward-search-line', tostring(vim.fn.line('.')),
                            pdf,
                        })
                    end
                end,
            },
        },
    },
}
