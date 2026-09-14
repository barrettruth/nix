vim.pack.add({
    'https://github.com/ibhagwan/fzf-lua',
}, { load = function() end })

return {
    'ibhagwan/fzf-lua',
    after = function()
        local fzf = require('fzf-lua')
        local actions = require('fzf-lua.actions')
        local has_rg = vim.fn.executable('rg') == 1
        local has_list = has_rg and vim.fn.executable('list') == 1
        local files_cmd = has_list and 'list --files'
            or has_rg and 'rg --files --no-config'
            or 'find . -type f -print'
        local grep_opts = {
            hidden = has_rg or nil,
            no_header_i = true,
            no_esc = true,
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
        }
        if has_list then
            grep_opts.cmd = table.concat({
                'list',
                '--column',
                '--line-number',
                '--no-heading',
                '--color=always',
                '--smart-case',
                '--max-columns=4096',
                '--fixed-strings',
                '-e',
            }, ' ')
            grep_opts.rg_glob = false
        end

        local opts = {
            ui_select = {},
            files = {
                cmd = files_cmd,
                hidden = true,
                no_header_i = true,
            },
            fzf_colors = true,
            keymap = {
                fzf = {
                    true,
                    ['ctrl-a'] = 'select-all',
                },
            },
            grep = grep_opts,
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
                worktrees = {
                    keymap = {
                        fzf = {
                            true,
                            ['ctrl-a'] = 'beginning-of-line',
                        },
                    },
                    actions = {
                        ['ctrl-d'] = {
                            fn = actions.git_worktree_del,
                            reload = true,
                        },
                    },
                },
                branches = {
                    keymap = {
                        fzf = {
                            true,
                            ['ctrl-a'] = 'beginning-of-line',
                        },
                    },
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
                local root = vim.fs.root(cwd, { '.git', '.jj' }) or cwd
                fzf.files({ cwd = root, cwd_prompt = false })
            end,
        },
        { '<c-g>', '<cmd>FzfLua live_grep<cr>' },
        { '<c-b>', '<cmd>FzfLua buffers<cr>' },
        {
            '<c-s-t>',
            function()
                require('fzf-lua').files({ cwd = vim.fn.expand('%:h') })
            end,
        },
        {
            '<c-s-g>',
            function()
                require('fzf-lua').live_grep({ cwd = vim.fn.expand('%:h') })
            end,
        },
        { '<leader>gb', '<cmd>FzfLua git_branches<cr>' },
        { '<leader>gc', '<cmd>FzfLua git_commits<cr>' },
        { '<leader>gC', '<cmd>FzfLua git_bcommits<cr>' },
        { '<leader>gw', '<cmd>FzfLua git_worktrees<cr>' },
        { '<c-s-h>', '<cmd>FzfLua highlights<cr>' },
        { '<c-h>', '<cmd>FzfLua help_tags<cr>' },
        { '<c-s-m>', '<cmd>FzfLua man_pages<cr>' },
        { '<c-r>', '<cmd>FzfLua resume<cr>' },
        { 'gQ', '<cmd>FzfLua quickfix<cr>' },
        { 'gL', '<cmd>FzfLua loclist<cr>' },
    },
}
