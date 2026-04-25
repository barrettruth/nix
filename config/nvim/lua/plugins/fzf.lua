vim.pack.add({
    'https://github.com/ibhagwan/fzf-lua',
}, { load = function() end })

return {
    'ibhagwan/fzf-lua',
    after = function()
        local fzf = require('fzf-lua')
        local actions = require('fzf-lua.actions')
        local utils = require('fzf-lua.utils')
        local preview = require('config.fzf.preview')
        local has_nonicons = pcall(require, 'nonicons')

        local function set_clipboard(text)
            local ok = pcall(vim.fn.setreg, '+', text)
            if not ok then
                pcall(vim.fn.setreg, '"', text)
            end
        end

        local function load_forge_ops()
            require('config.lz').load('barrettruth/forge.nvim')
            return require('forge.ops')
        end

        local function branch_name(selected)
            local line = selected and selected[1]
            if type(line) ~= 'string' or line == '' then
                return nil
            end
            if line:match('%(HEAD detached') or line:match('%(no branch') then
                return nil
            end
            local _, branch = line:match('%s-([%+%*]?)%s+([^ ]+)')
            if not branch then
                return nil
            end
            if branch:find('^remotes/') then
                branch = branch:match('remotes/.-/(.-)$') or branch
            end
            if branch == 'HEAD' or branch == '' then
                return nil
            end
            return branch
        end

        local function browse_branch(selected)
            local branch = branch_name(selected)
            if not branch then
                utils.warn('cannot browse detached HEAD')
                return
            end
            load_forge_ops().browse_branch(branch)
        end

        local function copy_branch(selected)
            local branch = branch_name(selected)
            if not branch then
                return
            end
            set_clipboard(branch)
            utils.info("Copied branch '%s'.", branch)
        end

        local function worktree_path(selected)
            local line = selected and selected[1]
            if type(line) ~= 'string' or line == '' then
                return nil
            end
            return line:match('^[^%s]+')
        end

        local function worktree_branch(selected)
            local line = selected and selected[1]
            if type(line) ~= 'string' or line == '' then
                return nil
            end
            return line:match('%[([^%]]+)%]')
        end

        local function browse_worktree(selected)
            local branch = worktree_branch(selected)
            if not branch then
                utils.warn('cannot browse detached worktree')
                return
            end
            load_forge_ops().browse_branch(branch)
        end

        local function copy_worktree(selected)
            local path = worktree_path(selected)
            if not path then
                return
            end
            set_clipboard(path)
            utils.info("Copied worktree path '%s'.", path)
        end

        local opts = {
            file_icon_padding = ' ',
            files = {
                cmd = vim.env.FZF_CTRL_T_COMMAND,
                no_header_i = true,
            },
            fzf_args = (vim.env.FZF_DEFAULT_OPTS or ''):gsub(
                '%-%-color=[^%s]+',
                ''
            ),
            grep = {
                no_header_i = true,
                RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
            },
            lsp = {
                includeDeclaration = false,
                jump1 = true,
                symbols = {
                    symbol_hl_prefix = '@',
                    symbol_style = 3,
                },
            },
            winopts = {
                border = 'single',
                fullscreen = true,
                title = false,
                preview = {
                    hidden = 'hidden',
                },
            },
            actions = {
                files = {
                    default = function(...)
                        require('fzf-lua.actions').file_edit(...)
                    end,
                    ['ctrl-l'] = function(...)
                        local a = require('fzf-lua.actions')
                        a.file_sel_to_ll(...)
                        vim.cmd.lclose()
                    end,
                    ['ctrl-q'] = function(...)
                        local a = require('fzf-lua.actions')
                        a.file_sel_to_qf(...)
                        vim.cmd.cclose()
                    end,
                    ['ctrl-h'] = function(...)
                        require('fzf-lua.actions').toggle_hidden(...)
                    end,
                    ['ctrl-v'] = function(...)
                        require('fzf-lua.actions').file_vsplit(...)
                    end,
                    ['ctrl-x'] = function(...)
                        require('fzf-lua.actions').file_split(...)
                    end,
                },
            },
            border = 'single',
            git = {
                files = {
                    cmd = 'git ls-files --cached --others --exclude-standard',
                    git_icons = false,
                },
                status = {
                    previewer = preview.status,
                    preview_pager = false,
                    winopts = { preview = { hidden = false } },
                },
                commits = {
                    previewer = preview.commits,
                    preview_pager = false,
                    winopts = { preview = { hidden = false } },
                },
                bcommits = {
                    previewer = preview.bcommits,
                    preview_pager = false,
                    winopts = { preview = { hidden = false } },
                },
                diff = {
                    previewer = preview.diff,
                    preview_pager = false,
                    winopts = { preview = { hidden = false } },
                },
                stash = {
                    previewer = preview.stash,
                    preview_pager = false,
                    winopts = { preview = { hidden = false } },
                },
                blame = {
                    previewer = preview.blame,
                    preview_pager = false,
                    winopts = { preview = { hidden = false } },
                },
                worktrees = {
                    fzf_args = (
                        (vim.env.FZF_DEFAULT_OPTS or '')
                            :gsub('%-%-bind=ctrl%-a:select%-all', '')
                            :gsub('--color=[^%s]+', '')
                    ),
                    actions = {
                        ['ctrl-x'] = browse_worktree,
                        ['ctrl-y'] = copy_worktree,
                        ['ctrl-d'] = {
                            fn = actions.git_worktree_del,
                            reload = true,
                        },
                    },
                },
                branches = {
                    fzf_args = (
                        (vim.env.FZF_DEFAULT_OPTS or '')
                            :gsub('%-%-bind=ctrl%-a:select%-all', '')
                            :gsub('--color=[^%s]+', '')
                    ),
                    actions = {
                        ['ctrl-x'] = browse_branch,
                        ['ctrl-y'] = copy_branch,
                        ['ctrl-d'] = {
                            fn = actions.git_branch_del,
                            reload = true,
                        },
                    },
                },
            },
        }

        opts.files.file_icons = has_nonicons and 'nonicons' or false
        opts.grep.file_icons = has_nonicons and 'nonicons' or false
        opts.grep.rg_opts =
            fzf.defaults.grep.rg_opts:gsub('%-e$', "--glob='!.git/' -e")

        fzf.setup(opts)

        local ok, fzf_reload = pcall(require, 'config.fzf.reload')
        if ok then
            fzf_reload.setup(opts)
            fzf_reload.reload()
        end
    end,
    cmd = 'FzfLua',
    keys = {
        {
            '<c-t>',
            function()
                local fzf = require('fzf-lua')
                local git_dir = vim.fn
                    .system('git rev-parse --git-dir 2>/dev/null')
                    :gsub('\n', '')
                if vim.v.shell_error == 0 and git_dir ~= '' then
                    fzf.git_files({ cwd_prompt = false })
                else
                    fzf.files()
                end
            end,
        },
        { '<c-l>', '<cmd>FzfLua live_grep<cr>' },
        { '<leader>f/', '<cmd>FzfLua search_history<cr>' },
        { '<leader>f:', '<cmd>FzfLua command_history<cr>' },
        { '<leader>fa', '<cmd>FzfLua autocmds<cr>' },
        { '<leader>fb', '<cmd>FzfLua buffers<cr>' },
        { '<leader>fc', '<cmd>FzfLua commands<cr>' },
        {
            '<leader>fe',
            '<cmd>FzfLua files cwd=~/.config<cr>',
        },
        {
            '<leader>ff',
            function()
                require('fzf-lua').files({ cwd = vim.fn.expand('%:h') })
            end,
        },
        {
            '<leader>fG',
            function()
                require('fzf-lua').live_grep({ cwd = vim.fn.expand('%:h') })
            end,
        },
        { '<leader>gb', '<cmd>FzfLua git_branches<cr>' },
        { '<leader>gc', '<cmd>FzfLua git_commits<cr>' },
        { '<leader>gC', '<cmd>FzfLua git_bcommits<cr>' },
        { '<leader>gs', '<cmd>FzfLua git_stash<cr>' },
        { '<leader>gw', '<cmd>FzfLua git_worktrees<cr>' },
        { '<leader>fH', '<cmd>FzfLua highlights<cr>' },
        { '<leader>fh', '<cmd>FzfLua help_tags<cr>' },
        { '<leader>fl', '<cmd>FzfLua loclist<cr>' },
        { '<leader>fm', '<cmd>FzfLua man_pages<cr>' },
        { '<leader>fq', '<cmd>FzfLua quickfix<cr>' },
        { '<leader>fr', '<cmd>FzfLua resume<cr>' },
        {
            '<leader>fs',
            '<cmd>FzfLua files cwd=~/.config/nix/scripts<cr>',
        },
        { 'gq', '<cmd>FzfLua quickfix<cr>' },
        { 'gl', '<cmd>FzfLua loclist<cr>' },
    },
}
