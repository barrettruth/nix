local dev_plugins = {
    'midnight.nvim',
    'live-server.nvim',
    'canola.nvim',
    'canola-collection',
    'pending.nvim',
    'cp.nvim',
    'diffs.nvim',
    'forge.nvim',
    'preview.nvim',
    'fzf-lua',
    'nvim-lspconfig',
}

local opt_dir = vim.fn.stdpath('data') .. '/site/pack/dev/opt/'
vim.fn.mkdir(opt_dir, 'p')
for _, name in ipairs(dev_plugins) do
    local link = opt_dir .. name
    if not vim.uv.fs_lstat(link) then
        vim.uv.fs_symlink(vim.fn.expand('~/dev/' .. name), link)
    end
end

local synctex_pdf = {}

return {
    {
        'barrettruth/forge.nvim',
        enabled = true,
        before = function()
            vim.g.forge = {
                ci = { lines = 5000 },
                keys = {
                    pr = {
                        checkout = '<cr>',
                        diff = '<c-d>',
                        worktree = '<c-w>',
                        ci = '<c-t>',
                        browse = '<c-x>',
                        manage = '<c-e>',
                        create = '<c-a>',
                        filter = '<c-o>',
                        refresh = '<c-r>',
                    },
                    issue = {
                        browse = '<cr>',
                        close = '<c-s>',
                        filter = '<c-o>',
                        refresh = '<c-r>',
                    },
                    commits = {
                        checkout = '<cr>',
                        diff = '<c-d>',
                        browse = '<c-x>',
                        yank = '<c-y>',
                    },
                },
                display = {
                    widths = {
                        title = 50,
                        author = 12,
                        name = 40,
                        branch = 20,
                    },
                    limits = {
                        pulls = 50,
                        issues = 50,
                        runs = 20,
                    },
                },
            }
        end,
        after = function()
            vim.cmd.packadd('fzf-lua')
        end,
        cmd = 'Forge',
        keys = { { '<c-g>', '<cmd>Forge<cr>' } },
    },
    {
        'barrettruth/diffs.nvim',
        enabled = true,
        before = function()
            vim.g.diffs = {
                debug = false,
                integrations = { fugitive = true },
                extra_filetypes = { 'diff', 'git', 'gitcommit' },
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
                        algorithm = 'vscode',
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
        branch = 'canola',
        enabled = true,
        before = function()
            vim.g.canola = {
                columns = {},
                highlights = { filename = {}, columns = true },
                confirm = true,
                save = 'auto',
                extglob = true,
                delete = { wipe = true, recursive = true, trash = true },
                float = { border = 'single' },
                keymaps = {
                    ['<c-h>'] = false,
                    ['<c-t>'] = false,
                    ['<c-l>'] = false,
                    ['<c-r>'] = 'actions.refresh',
                    ['<c-x>'] = {
                        callback = 'actions.select',
                        opts = { horizontal = true },
                    },
                },
            }
        end,
        after = function()
            vim.cmd.packadd('canola-collection')

            local show_all = false
            vim.api.nvim_create_autocmd('FileType', {
                pattern = 'canola',
                callback = function(args)
                    local bufnr = args.buf

                    vim.keymap.set('n', 'gC', function()
                        show_all = not show_all
                        if show_all then
                            require('canola').set_columns({
                                'git_status',
                                'permissions',
                                'owner',
                                'size',
                                'mtime',
                            })
                        else
                            require('canola').set_columns({})
                        end
                    end, {
                        buffer = bufnr,
                        desc = 'toggle columns',
                    })

                    vim.keymap.set('n', 'gX', function()
                        local canola = require('canola')
                        local entry = canola.get_cursor_entry()
                        local dir = canola.get_current_dir()
                        if not entry or not dir then
                            return
                        end
                        local path = dir .. entry.name
                        vim.ui.input(
                            { prompt = 'chmod: ', default = '755' },
                            function(mode)
                                if not mode then
                                    return
                                end
                                vim.uv.fs_chmod(
                                    path,
                                    tonumber(mode, 8),
                                    function(err)
                                        if err then
                                            vim.schedule(function()
                                                vim.notify(
                                                    err,
                                                    vim.log.levels.ERROR
                                                )
                                            end)
                                            return
                                        end
                                        vim.schedule(function()
                                            require('canola.actions').refresh.callback()
                                        end)
                                    end
                                )
                            end
                        )
                    end, {
                        buffer = bufnr,
                        desc = 'chmod entry',
                    })
                end,
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
            vim.g.pending = {
                view = {
                    calendar = {
                        first_day = 'sunday',
                        day_format = '%a %d/%m',
                        title_format = '%d/%m/%Y',
                    },
                    queue = {
                        sort = {
                            'status',
                            'due',
                            'priority',
                            'order',
                            'id',
                        },
                    },
                    category = { hide_done_categories = true },
                },
                debug = false,
                sync = {
                    s3 = { bucket = 'pending.nvim', region = 'us-east-1' },
                },
                data_path = (
                    os.getenv('XDG_STATE_HOME')
                    or (os.getenv('HOME') .. '/.local/state')
                ) .. '/nvim/pending/tasks.json',
                date_format = '%d/%m/%Y',
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
            vim.api.nvim_create_autocmd('User', {
                pattern = 'PreviewWatchingStopped',
                callback = function(args)
                    synctex_pdf[args.data.bufnr] = nil
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
                    args = function(ctx)
                        local dir = vim.fn.fnamemodify(ctx.file, ':h')
                            .. '/build'
                        vim.fn.mkdir(dir, 'p')
                        return {
                            '-pdf',
                            '-interaction=nonstopmode',
                            '-synctex=1',
                            '-output-directory=' .. dir,
                            '-pdflatex=pdflatex -file-line-error %O %S',
                            ctx.file,
                        }
                    end,
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
