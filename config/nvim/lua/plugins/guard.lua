vim.pack.add({
    'https://github.com/nvimdev/guard.nvim',
    'https://github.com/nvimdev/guard-collection',
}, { load = function() end })

return {
    'nvimdev/guard.nvim',
    before = function()
        require('config.lz').load('guard-collection')
        vim.g.guard_config = {
            fmt_on_save = false,
            save_on_fmt = true,
            lsp_as_default_formatter = true,
        }
    end,
    keys = {
        { 'gF', '<cmd>Guard fmt<cr>', mode = { 'n', 'x' } },
    },
    after = function()
        local ft = require('guard.filetype')

        ft('python')
            :fmt({
                cmd = 'isort',
                args = { '--profile', 'black', '-' },
                stdin = true,
            })
            :fmt('black')
            :lint('mypy')

        ft('lua'):fmt('stylua'):lint('selene')

        ft('javascript,javascriptreact,typescript,typescriptreact')
            :fmt('prettierd')
            :lint('eslint_d')
        ft('css,graphql,html,json,jsonc,mdx,toml,yaml'):fmt('prettierd')

        ft('sh,bash,zsh'):fmt({
            cmd = 'shfmt',
            args = { '-i', '2' },
            stdin = true,
        })
        ft('sh,bash'):lint('shellcheck')
        ft('zsh'):lint('zsh')

        ft('html,astro'):fmt('prettierd')

        ft('proto'):fmt('buf'):lint('buf')
        ft('dockerfile'):lint('hadolint')
        ft('typst'):fmt('typstyle')
        ft('cmake'):fmt('cmake-format')
        ft('make'):lint('checkmake')
        local cpplint = vim.deepcopy(require('guard-collection.linter.cpplint'))
        cpplint.ignore_patterns = require('config.cp').root_pattern
        ft('cpp'):lint(cpplint)
        ft('markdown'):fmt('prettierd')

        if vim.fn.executable('buildifier') == 1 then
            ft('bzl'):fmt({
                cmd = 'buildifier',
                args = { '-path' },
                fname = true,
                stdin = true,
            })
        end

        local lint = require('guard.lint')

        ft('nix')
            :fmt({
                cmd = 'nix',
                args = { 'fmt', '--', '--stdin' },
                stdin = true,
                fname = true,
            })
            :lint({
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
            })
            :lint({
                cmd = 'statix',
                args = { 'check', '-o', 'json' },
                fname = true,
                parse = lint.from_json({
                    get_diagnostics = function(raw)
                        local data = vim.json.decode(raw)
                        local results = {}
                        for _, entry in ipairs(data.report or {}) do
                            for _, diag in ipairs(entry.diagnostics or {}) do
                                table.insert(results, {
                                    from_line = diag.at.from.line,
                                    from_col = diag.at.from.column,
                                    to_line = diag.at.to.line,
                                    to_col = diag.at.to.column,
                                    message = entry.note,
                                    severity = entry.severity,
                                })
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
            })
    end,
}
