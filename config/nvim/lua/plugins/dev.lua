local dev_plugins = {
    { 'canola.nvim', 'canola.nvim/.worktrees/canola' },
    'midnight.nvim',
    'diffs.nvim',
    'preview.nvim',
    'ci.nvim',
    'forge.nvim',
}

local function current_colorscheme()
    local state_home = vim.env.XDG_STATE_HOME
        or (vim.env.HOME and (vim.env.HOME .. '/.local/state'))

    if not state_home then
        return 'midnight'
    end

    local ok, lines = pcall(vim.fn.readfile, state_home .. '/theme')
    local theme = ok and lines[1] or nil

    return theme == 'daylight' and 'daylight' or 'midnight'
end

local opt_dir = vim.fn.stdpath('data') .. '/site/pack/dev/opt/'
vim.fn.mkdir(opt_dir, 'p')
for _, plugin in ipairs(dev_plugins) do
    local name = type(plugin) == 'table' and plugin[1] or plugin
    local path = type(plugin) == 'table' and plugin[2] or plugin
    local link = opt_dir .. name
    if not vim.uv.fs_lstat(link) then
        vim.uv.fs_symlink(vim.fn.expand('~/dev/' .. path), link)
    end
end

return {
    {
        'barrettruth/ci.nvim',
        cmd = 'CI',
    },
    {
        'barrettruth/forge.nvim',
        cmd = { 'Issue', 'PR' },
    },
    {
        'barrettruth/canola.nvim',
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
            vim.api.nvim_create_autocmd('FileType', {
                pattern = 'canola',
                group = vim.api.nvim_create_augroup('ACanola', { clear = true }),
                callback = function(args)
                    local bufnr = args.buf

                    vim.keymap.set('n', 'gC', function()
                        local canola = require('canola')
                        if #require('canola.config').columns == 0 then
                            canola.set_columns({
                                'git_status',
                                'permissions',
                                'owner',
                                'size',
                                'mtime',
                            })
                        else
                            canola.set_columns({})
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
        'barrettruth/diffs.nvim',
        enabled = true,
        before = function()
            require('config.lz').load('barrettruth/midnight.nvim')

            vim.g.diffs = {
                debug = false,
                integrations = {
                    difftastic = false,
                    fugitive = true,
                    gitsigns = true,
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
            vim.cmd.colorscheme(current_colorscheme())

            vim.api.nvim_create_autocmd('OptionSet', {
                pattern = 'background',
                group = vim.api.nvim_create_augroup('ATheme', { clear = true }),
                callback = function()
                    local colorscheme = vim.o.background == 'light'
                            and 'daylight'
                        or 'midnight'
                    if vim.g.colors_name ~= colorscheme then
                        vim.cmd.colorscheme(colorscheme)
                    end
                end,
            })
        end,
    },
    {
        'barrettruth/preview.nvim',
        ft = { 'typst', 'markdown' },
        before = function()
            vim.g.preview = {
                debug = false,
                github = {
                    output = function(ctx)
                        return '/tmp/'
                            .. vim.fn.fnamemodify(ctx.file, ':t:r')
                            .. '.html'
                    end,
                },
                typst = {
                    open = { vim.fn.has('mac') == 1 and 'open' or 'zathura' },
                },
            }
        end,
        keys = {
            {
                '<leader>p',
                '<Plug>(preview-toggle)',
                desc = 'toggle preview',
            },
        },
    },
}
