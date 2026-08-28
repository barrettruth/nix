local ns = vim.api.nvim_create_namespace('highlight_undo')
local timeout = 300

vim.api.nvim_set_hl(0, 'HighlightUndo', { link = 'IncSearch', default = true })

for key, action in pairs({ u = 'u', U = '<c-r>' }) do
    vim.keymap.set('n', key, function()
        local count = vim.v.count == 0 and '' or tostring(vim.v.count)
        if not vim.bo.modifiable then
            vim.api.nvim_feedkeys(count .. vim.keycode(action), 'n', false)
            return
        end
        local active = true
        vim.api.nvim_buf_attach(0, false, {
            on_bytes = function(_, buf, _, sr, sc, _, _, _, _, ner, nec)
                if not active then
                    return true
                end
                active = false
                local er = sr + ner
                local ec = ner == 0 and sc + nec or nec
                if er >= vim.api.nvim_buf_line_count(buf) then
                    ec = #(
                        vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ''
                    )
                end
                vim.schedule(function()
                    if not vim.api.nvim_buf_is_valid(buf) then
                        return
                    end
                    vim.hl.range(
                        buf,
                        ns,
                        'HighlightUndo',
                        { sr, sc },
                        { er, ec },
                        { timeout = timeout }
                    )
                end)
                return true
            end,
        })
        local ok, err = pcall(
            vim.cmd.normal,
            { args = { count .. vim.keycode(action) }, bang = true }
        )
        active = false
        if not ok then
            vim.notify((tostring(err):gsub('^Vim:', '')), vim.log.levels.ERROR)
        end
    end, { desc = 'undo/redo with highlight' })
end
