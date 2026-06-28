local dev_plugins = {
    'midnight.nvim',
    -- 'canola.nvim',
    -- 'canola-collection',
    'pending.nvim',
    'diffs.nvim',
    'preview.nvim',
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

return {
    {
        'barrettruth/diffs.nvim',
        enabled = true,
        before = function()
            require('config.lz').load('barrettruth/midnight.nvim')

            vim.g.diffs = {
                debug = false,
                integrations = {
                    difftastic = false,
                    fugitive = true,
                },
                extra_filetypes = { 'diff' },
                view = { prefix = false },
                highlights = {
                    background = true,
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
    --[[
    {
        'barrettruth/canola.nvim',
        branch = 'canola',
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
    --]]
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
