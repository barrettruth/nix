vim.pack.add({
    'https://github.com/ibhagwan/fzf-lua',
}, { load = function() end })

return {
    'ibhagwan/fzf-lua',
    after = function()
        local fzf = require('fzf-lua')
        local actions = require('fzf-lua.actions')

        local opts = {
            files = {
                cmd = vim.env.FZF_CTRL_T_COMMAND,
                no_header_i = true,
            },
            fzf_colors = true,
            grep = {
                no_header_i = true,
                no_esc = true,
                RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
                rg_opts = fzf.defaults.grep.rg_opts:gsub(
                    '%-e$',
                    "--fixed-strings --glob='!.git/' --glob='!.jj/' -e"
                ),
                actions = {
                    ['ctrl-r'] = {
                        fn = function(selected, opts)
                            actions.toggle_flag(
                                selected,
                                vim.tbl_extend('force', opts, {
                                    toggle_flag = '--fixed-strings',
                                })
                            )
                        end,
                        desc = 'toggle regex',
                    },
                },
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
                worktrees = {
                    fzf_args = (vim.env.FZF_DEFAULT_OPTS or ''):gsub(
                        '%-%-bind=ctrl%-a:select%-all',
                        ''
                    ),
                    actions = {
                        ['ctrl-d'] = {
                            fn = actions.git_worktree_del,
                            reload = true,
                        },
                    },
                },
                branches = {
                    fzf_args = (vim.env.FZF_DEFAULT_OPTS or ''):gsub(
                        '%-%-bind=ctrl%-a:select%-all',
                        ''
                    ),
                    actions = {
                        ['ctrl-d'] = {
                            fn = actions.git_branch_del,
                            reload = true,
                        },
                    },
                },
            },
        }

        fzf.setup(opts)
    end,
    cmd = 'FzfLua',
    keys = {
        {
            '<c-t>',
            function()
                local fzf = require('fzf-lua')
                local cwd = vim.fn.getcwd()
                local git_root = vim.fs.root(cwd, '.git')
                local jj_root = vim.fs.root(cwd, '.jj')
                if git_root then
                    fzf.git_files({ cwd_prompt = false })
                elseif jj_root then
                    fzf.files({ cwd = jj_root, cwd_prompt = false })
                else
                    fzf.files()
                end
            end,
        },
        { '<c-l>', '<cmd>FzfLua live_grep<cr>' },
        { '<leader>fb', '<cmd>FzfLua buffers<cr>' },
        {
            '<leader>ft',
            function()
                require('fzf-lua').files({ cwd = vim.fn.expand('%:h') })
            end,
        },
        {
            '<leader>fg',
            function()
                require('fzf-lua').live_grep({ cwd = vim.fn.expand('%:h') })
            end,
        },
        { '<leader>gb', '<cmd>FzfLua git_branches<cr>' },
        { '<leader>gc', '<cmd>FzfLua git_commits<cr>' },
        { '<leader>gC', '<cmd>FzfLua git_bcommits<cr>' },
        { '<leader>gw', '<cmd>FzfLua git_worktrees<cr>' },
        { '<leader>fH', '<cmd>FzfLua highlights<cr>' },
        { '<leader>fh', '<cmd>FzfLua help_tags<cr>' },
        { '<leader>fm', '<cmd>FzfLua man_pages<cr>' },
        { '<leader>fr', '<cmd>FzfLua resume<cr>' },
        {
            '<leader>fs',
            '<cmd>FzfLua files cwd=~/.config/nix/scripts<cr>',
        },
        { 'gQ', '<cmd>FzfLua quickfix<cr>' },
        { 'gL', '<cmd>FzfLua loclist<cr>' },
    },
}
