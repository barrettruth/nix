vim.pack.add({
    'https://github.com/nvimdev/guard.nvim',
    'https://github.com/nvimdev/guard-collection',
}, { confirm = false, load = true })

local ft = require('guard.filetype')
local lint = require('guard.lint')

ft('lua')
    :fmt('stylua')
    :extra('--config-path', 'config/nvim/stylua.toml')
    :lint('selene')
ft('python'):fmt('black')

local deadnix = {
    cmd = 'deadnix',
    args = { '-o', 'json' },
    fname = true,
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
        },
        source = 'deadnix',
    }),
}

local statix = {
    cmd = 'statix',
    args = { 'check', '-o', 'json' },
    fname = true,
    parse = lint.from_json({
        get_diagnostics = function(raw)
            local data = vim.json.decode(raw)
            local results = {}
            for _, entry in ipairs(data.report or {}) do
                for _, diagnostic in ipairs(entry.diagnostics or {}) do
                    results[#results + 1] = {
                        from_line = diagnostic.at.from.line,
                        from_col = diagnostic.at.from.column,
                        to_line = diagnostic.at.to.line,
                        to_col = diagnostic.at.to.column,
                        message = entry.note,
                        severity = entry.severity,
                    }
                end
            end
            return results
        end,
        attributes = {
            lnum = 'from_line',
            col = 'from_col',
            lnum_end = 'to_line',
            col_end = 'to_col',
            message = 'message',
        },
        severities = {
            Error = lint.severities.error,
            Warn = lint.severities.warning,
            Hint = lint.severities.info,
        },
        source = 'statix',
    }),
}

ft('nix')
    :fmt({
        cmd = 'nix',
        args = { 'fmt', '--', '--stdin' },
        stdin = true,
        fname = true,
    })
    :lint(deadnix)
    :append(statix)
