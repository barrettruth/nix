vim.pack.add({
    'https://github.com/nvimdev/guard.nvim',
    'https://github.com/nvimdev/guard-collection',
}, { confirm = false, load = true })

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
local ft = require('guard.filetype')
local lint = require('guard.lint')

ft('nix'):fmt({
    cmd = 'nix',
    args = { 'fmt', '--', '--tree-root', root, '--stdin' },
    stdin = true,
    fname = true,
}):lint({
    cmd = 'deadnix',
    args = {
        '--no-lambda-pattern-names',
        '--output-format',
        'json',
        '/dev/stdin',
    },
    stdin = true,
    parse = lint.from_json({
        get_diagnostics = function(raw)
            return vim.json.decode(raw).results
        end,
        attributes = {
            lnum = 'line',
            col = 'column',
            lnum_end = 'line',
            col_end = 'endColumn',
            message = 'message',
            severity = function()
                return 'warning'
            end,
        },
        source = 'deadnix',
    }),
})

ft('sh,bash'):fmt({
    cmd = 'shfmt',
    args = { '-i', '2', '--filename' },
    stdin = true,
    fname = true,
}):lint({
    cmd = 'shellcheck',
    args = { '--format', 'json1' },
    fname = true,
    parse = lint.from_json({
        get_diagnostics = function(raw)
            return vim.json.decode(raw).comments
        end,
        attributes = {
            lnum_end = 'endLine',
            col_end = 'endColumn',
            severity = 'level',
        },
        source = 'shellcheck',
    }),
})

ft('python'):fmt({
    cmd = 'black',
    args = { '--quiet', '-', '--stdin-filename' },
    stdin = true,
    fname = true,
})

ft('lua'):fmt({
    cmd = 'stylua',
    args = { '--config-path', root .. '/config/nvim/stylua.toml', '-' },
    stdin = true,
})

ft('markdown,yaml'):fmt({
    cmd = 'prettier',
    args = { '--stdin-filepath' },
    stdin = true,
    fname = true,
})

vim.lsp.enable({ 'lua_ls', 'basedpyright', 'ty', 'nixd' })
