return {
    'saghen/blink.cmp',
    version = '1.*',
    dependencies = {
        'Kaiser-Yang/blink-cmp-git',
        'folke/lazydev.nvim',
        'bydlw98/blink-cmp-env',
        { 'barrettruth/blink-cmp-ssh', dir = '~/dev/blink-cmp-ssh' },
        { 'barrettruth/blink-cmp-tmux', dir = '~/dev/blink-cmp-tmux' },
        { 'barrettruth/blink-cmp-ghostty', dir = '~/dev/blink-cmp-ghostty' },
    },
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    event = { 'InsertEnter', 'LspAttach' },
    config = function(_, opts)
        vim.o.pumheight = 15
        opts.completion.menu.max_height = vim.o.pumheight

        require('config.blink')
        require('blink.cmp').setup(opts)
    end,
    opts = {
        keymap = {
            ['<c-p>'] = { 'select_prev' },
            ['<c-n>'] = { 'show', 'select_next' },
            ['<c-space>'] = {},
            ['<c-y>'] = {
                function(cmp)
                    return cmp.snippet_active() and cmp.accept()
                        or cmp.select_and_accept()
                end,
                'snippet_forward',
            },
        },
        completion = {
            accept = {
                auto_brackets = { enabled = false },
            },
            documentation = {
                auto_show = true,
                window = {
                    border = 'single',
                    scrollbar = false,
                },
            },
            menu = {
                auto_show = false,
                border = 'single',
                scrollbar = false,
                draw = {
                    treesitter = { 'lsp', 'snippets', 'buffer' },
                    columns = {
                        { 'label', 'label_description', gap = 1 },
                        { 'kind' },
                    },
                    components = {
                        kind = {
                            ellipsis = false,
                            text = function(ctx)
                                return '[' .. ctx.kind .. ']'
                            end,
                            highlight = function(ctx)
                                return ctx.kind_hl
                            end,
                        },
                    },
                },
            },
            ghost_text = {
                enabled = true,
                show_with_selection = true,
                show_without_selection = false,
                show_without_menu = false,
            },
        },
        sources = {
            default = {
                'git',
                'conventional_commits',
                'lsp',
                'path',
                'buffer',
                'env',
                'snippets',
                'ssh',
                'tmux',
                'ghostty',
            },
            providers = {
                git = {
                    module = 'blink-cmp-git',
                    name = 'Git',
                },
                ssh = {
                    name = 'SSH',
                    module = 'blink-cmp-ssh',
                },
                tmux = {
                    name = 'Tmux',
                    module = 'blink-cmp-tmux',
                },
                ghostty = {
                    name = 'Ghostty',
                    module = 'blink-cmp-ghostty',
                },
                conventional_commits = {
                    name = 'Conventional Commits',
                    module = 'config.blink.conventional_commits',
                },
                lazydev = {
                    name = 'LazyDev',
                    module = 'lazydev.integrations.blink',
                    score_offset = 100,
                },
                env = {
                    name = 'Env',
                    module = 'blink-cmp-env',
                },
            },
        },
    },
    keys = { { '<c-n>', mode = 'i' } },
    opts_extend = { 'sources.default' },
}
