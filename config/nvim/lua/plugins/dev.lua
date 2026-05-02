local dev_plugins = {
    'midnight.nvim',
    'canola.nvim',
    'canola-collection',
    'pending.nvim',
    'cp.nvim',
    'diffs.nvim',
    'forge.nvim',
    'nonicons.nvim',
    'preview.nvim',
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
local synctex_socket = '/tmp/nvim-preview.sock'

local function ensure_synctex_server()
    if vim.tbl_contains(vim.fn.serverlist(), synctex_socket) then
        return
    end
    if vim.uv.fs_stat(synctex_socket) then
        local probe = vim.system(
            { 'nvim', '--server', synctex_socket, '--remote-expr', '1' },
            { text = true }
        ):wait()
        if probe.code == 0 then
            return
        end
        vim.fn.delete(synctex_socket)
    end
    local ok, err = pcall(vim.fn.serverstart, synctex_socket)
    if not ok then
        vim.notify(err, vim.log.levels.WARN)
    end
end

local function forward_search_zathura()
    local pdf = synctex_pdf[vim.api.nvim_get_current_buf()]
    if not pdf then
        return
    end
    vim.fn.jobstart({
        'zathura',
        '--synctex-forward',
        vim.fn.line('.') .. ':0:' .. vim.fn.expand('%:p'),
        pdf,
    })
end

local function load_forge()
    require('config.lz').load('barrettruth/forge.nvim')
    return require('forge')
end

local function edit_or_create_pr()
    local forge = load_forge()
    local detected = forge.detect()
    if not detected then
        require('forge.logger').warn('no forge detected')
        return
    end
    local pr, err = forge.current_pr({ forge = detected })
    if err then
        require('forge.logger').warn(err.message or 'current PR lookup failed')
        return
    end
    if pr then
        forge.pr(pr)
    else
        forge.create_pr()
    end
end

return {
    {
        'barrettruth/forge.nvim',
        enabled = true,
        after = function()
            require('config.lz').load('ibhagwan/fzf-lua')
        end,
        cmd = 'Forge',
        keys = {
            {
                '<leader>gg',
                function()
                    load_forge().open()
                end,
                desc = 'forge menu',
            },
            {
                '<leader>gi',
                function()
                    load_forge().open('issues.open')
                end,
                desc = 'forge issues',
            },
            {
                '<leader>gx',
                ':Forge browse<cr>',
                mode = { 'n', 'x' },
                desc = 'forge browse',
            },
            {
                '<leader>ge',
                edit_or_create_pr,
                desc = 'forge edit or create pr',
            },
            {
                '<leader>go',
                function()
                    load_forge().open('prs.open')
                end,
                desc = 'forge prs',
            },
            {
                '<leader>gt',
                function()
                    load_forge().pr_ci()
                end,
                desc = 'forge pr checks',
            },
            {
                '<leader>gr',
                '<cmd>Forge review adapter=browse<cr>',
                desc = 'forge browse pr',
            },
        },
    },
    {
        'barrettruth/diffs.nvim',
        enabled = true,
        keys = {
            { 'gtd', '<Plug>(diffs-gdiff)', desc = 'diffs gdiff' },
            { 'gtD', '<Plug>(diffs-gvdiff)', desc = 'diffs gvdiff' },
        },
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
                    },
                    intra = {
                        enabled = true,
                        algorithm = 'vscode',
                        max_lines = 500,
                    },
                },
                conflict = {
                    keymaps = {
                        ours = 'gto',
                        theirs = 'gtt',
                        both = 'gtb',
                        none = 'gt0',
                        next = ']x',
                        prev = '[x',
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
        'barrettruth/canola.nvim',
        branch = 'canola',
        enabled = true,
        before = function()
            vim.g.canola = {
                columns = {},
                highlights = { columns = true },
                confirm = true,
                save = 'auto',
                extglob = true,
                delete = { wipe = true, recursive = true },
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
            require('config.lz').load('canola-collection')

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

                    vim.api.nvim_buf_create_user_command(
                        bufnr,
                        'CanolaChmod',
                        function(cmd_args)
                            local canola = require('canola')
                            local dir = canola.get_current_dir()
                            if not dir then
                                return
                            end

                            local mode = cmd_args.args ~= '' and cmd_args.args
                                or '+x'
                            local cmd = { 'chmod', mode, '--' }
                            for lnum = cmd_args.line1, cmd_args.line2 do
                                local entry = canola.get_entry_on_line(0, lnum)
                                if entry then
                                    cmd[#cmd + 1] = dir .. entry.name
                                end
                            end
                            if #cmd == 3 then
                                return
                            end

                            vim.system(cmd, { text = true }, function(result)
                                vim.schedule(function()
                                    if result.code ~= 0 then
                                        local stderr =
                                            vim.trim(result.stderr or '')
                                        vim.notify(
                                            stderr ~= '' and stderr
                                                or 'chmod failed',
                                            vim.log.levels.ERROR
                                        )
                                        return
                                    end
                                    require('canola.actions').refresh.callback({
                                        force = true,
                                    })
                                end)
                            end)
                        end,
                        { range = true, nargs = '?', force = true }
                    )

                    vim.keymap.set({ 'n', 'x' }, 'gX', ':CanolaChmod +x<cr>', {
                        buffer = bufnr,
                        desc = 'chmod +x entry',
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
            require('config.lz').load('ibhagwan/fzf-lua')
        end,
    },
    {
        'barrettruth/preview.nvim',
        ft = { 'typst', 'tex', 'markdown', 'plantuml' },
        before = function()
            ensure_synctex_server()

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
                    forward_search_zathura()
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
                typst = { open = { 'zathura' } },
                plantuml = true,
                mermaid = true,
                latex = {
                    open = { 'zathura' },
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
