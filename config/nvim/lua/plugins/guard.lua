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

        if vim.fn.executable('isort') == 1 then
            ft('python'):fmt({
                cmd = 'isort',
                args = { '--profile', 'black', '-' },
                stdin = true,
            })
            if vim.fn.executable('black') == 1 then
                ft('python'):append('black')
            end
        elseif vim.fn.executable('black') == 1 then
            ft('python'):fmt('black')
        end
        if vim.fn.executable('mypy') == 1 then
            ft('python'):lint('mypy')
        end

        if vim.fn.executable('stylua') == 1 then
            ft('lua'):fmt('stylua')
        end
        if vim.fn.executable('selene') == 1 then
            ft('lua'):lint('selene')
        end

        local web = 'javascript,javascriptreact,typescript,typescriptreact'
        if vim.fn.executable('prettierd') == 1 then
            ft(web):fmt('prettierd')
            ft('css,graphql,html,json,jsonc,mdx,toml,yaml'):fmt('prettierd')
            ft('html,astro'):fmt('prettierd')
            ft('markdown'):fmt('prettierd')
        end
        if vim.fn.executable('shfmt') == 1 then
            ft('sh,bash,zsh'):fmt({
                cmd = 'shfmt',
                args = { '-i', '2' },
                stdin = true,
            })
        end
        if vim.fn.executable('shellcheck') == 1 then
            ft('sh,bash'):lint('shellcheck')
        end
        if vim.fn.executable('zsh') == 1 then
            ft('zsh'):lint('zsh')
        end

        if vim.fn.executable('buf') == 1 then
            ft('proto'):fmt('buf'):lint('buf')
        end
        if vim.fn.executable('hadolint') == 1 then
            ft('dockerfile'):lint('hadolint')
        end
        if vim.fn.executable('typstyle') == 1 then
            ft('typst'):fmt('typstyle')
        end
        if vim.fn.executable('cmake-format') == 1 then
            ft('cmake'):fmt('cmake-format')
        end
        if vim.fn.executable('checkmake') == 1 then
            ft('make'):lint('checkmake')
        end

        if vim.fn.executable('buildifier') == 1 then
            ft('bzl'):fmt({
                cmd = 'buildifier',
                args = { '-path' },
                fname = true,
                stdin = true,
            })
        end
        if vim.fn.executable('ktfmt') == 1 then
            ft('kotlin'):fmt({
                cmd = 'ktfmt',
                args = { '--kotlinlang-style', '-' },
                stdin = true,
            })
        end

        local lint = require('guard.lint')

        if vim.fn.executable('nix') == 1 then
            ft('nix'):fmt({
                cmd = 'nix',
                args = { 'fmt', '--', '--stdin' },
                stdin = true,
                fname = true,
            })
        end

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
        }

        if vim.fn.executable('deadnix') == 1 then
            ft('nix'):lint(deadnix)
            if vim.fn.executable('statix') == 1 then
                ft('nix'):append(statix)
            end
        elseif vim.fn.executable('statix') == 1 then
            ft('nix'):lint(statix)
        end
    end,
}
