local dev_plugins = {
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

    if theme == 'daylight' or theme == 'bright' or theme == 'light' then
        return 'daylight'
    end

    return 'midnight'
end

local opt_dir = vim.fn.stdpath('data') .. '/site/pack/dev/opt/'
vim.fn.mkdir(opt_dir, 'p')
for _, name in ipairs(dev_plugins) do
    local link = opt_dir .. name
    if not vim.uv.fs_lstat(link) then
        vim.uv.fs_symlink(vim.fn.expand('~/dev/' .. name), link)
    end
end

return {
    {
        'barrettruth/ci.nvim',
        cmd = 'CI',
        before = function()
            vim.g.ci = {
                debug = false,
            }
        end,
    },
    {
        'barrettruth/forge.nvim',
        cmd = { 'Issue', 'PR' },
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
                group = vim.api.nvim_create_augroup('Theme', { clear = true }),
                callback = function()
                    local want = vim.o.background == 'light' and 'daylight'
                        or 'midnight'
                    if vim.g.colors_name ~= want then
                        vim.cmd.colorscheme(want)
                    end
                end,
            })
        end,
    },
    {
        'barrettruth/preview.nvim',
        ft = { 'typst', 'tex', 'markdown' },
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
            {
                '<leader>p',
                '<Plug>(preview-toggle)',
                desc = 'toggle preview',
            },
        },
    },
}
