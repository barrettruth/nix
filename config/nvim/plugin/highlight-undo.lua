local ns = vim.api.nvim_create_namespace('highlight_undo')
local timeout = 300

vim.api.nvim_set_hl(0, 'HighlightUndo', { link = 'IncSearch', default = true })

for _, key in ipairs({ 'u', '<c-r>', 'U' }) do
    vim.keymap.set('n', key, function()
        local count = vim.v.count == 0 and '' or tostring(vim.v.count)
        -- A buffer that cannot change has nothing to highlight, and wrapping
        -- the key there reports Vim's own E21 as a lua error with a traceback.
        if not vim.bo.modifiable then
            vim.api.nvim_feedkeys(count .. vim.keycode(key), 'n', false)
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
        -- Always stop listening. When the undo fails the callback never fires,
        -- and an attach left armed highlights whatever changes the buffer next.
        local ok, err = pcall(
            vim.cmd.normal,
            { args = { count .. vim.keycode(key) }, bang = true }
        )
        active = false
        if not ok then
            vim.notify((tostring(err):gsub('^Vim:', '')), vim.log.levels.ERROR)
        end
    end, { desc = 'undo/redo with highlight' })
end
