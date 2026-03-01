vim.pack.add({
    { src = 'https://github.com/saghen/blink.cmp', load = false },
    { src = 'https://github.com/Kaiser-Yang/blink-cmp-git', load = false },
    { src = 'https://github.com/bydlw98/blink-cmp-env', load = false },
    { src = 'https://github.com/barrettruth/blink-cmp-ssh', load = false },
    { src = 'https://github.com/barrettruth/blink-cmp-tmux', load = false },
    { src = 'https://github.com/barrettruth/blink-cmp-ghostty', load = false },
})

local pack_dir = vim.fn.stdpath('data') .. '/site/pack/core/opt'
local blink_dir = pack_dir .. '/blink.cmp'
if
    vim.fn.filereadable(blink_dir .. '/target/release/libblink_cmp_fuzzy.so')
    == 0
then
    vim.system({ 'nix', 'run', '.#build-plugin' }, { cwd = blink_dir }):wait()
end

vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
        local name, kind = ev.data.spec.name, ev.data.kind
        if kind == 'delete' then
            return
        end
        if name == 'blink.cmp' then
            vim.system(
                { 'nix', 'run', '.#build-plugin' },
                { cwd = ev.data.path }
            )
        end
    end,
})

return {
    'saghen/blink.cmp',
    event = { 'InsertEnter', 'LspAttach' },
    keys = { { '<c-n>', mode = 'i' } },
    after = function()
        ---@module 'blink.cmp'
        ---@type blink.cmp.Config
        local opts = {
            fuzzy = { implementation = 'prefer_rust_with_warning' },
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
                per_filetype = {
                    pending = { 'omni', 'buffer' },
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
                        module = 'config.cmp.conventional_commits',
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
        }

        vim.o.pumheight = 15
        opts.completion.menu.max_height = vim.o.pumheight

        require('config.cmp')
        require('blink.cmp').setup(opts)
    end,
}
