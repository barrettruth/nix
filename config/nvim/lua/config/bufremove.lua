-- https://github.com/echasnovski/mini.bufremove/blob/main/lua/mini/bufremove.lua

---@param wipeout? boolean
return function(wipeout)
    local buf = vim.api.nvim_get_current_buf()
    local cmd = wipeout and 'bwipeout' or 'bdelete'

    if vim.bo[buf].modified then
        local ok = vim.fn.confirm(
            ('Buffer %d has unsaved changes. Force %s?'):format(buf, cmd),
            '&No\n&Yes',
            1,
            'Question'
        ) == 2
        if not ok then
            return
        end
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        vim.api.nvim_win_call(win, function()
            if vim.fn.getcmdwintype() ~= '' then
                vim.cmd('close!')
                return
            end
            local alt = vim.fn.bufnr('#')
            if alt ~= buf and vim.fn.buflisted(alt) == 1 then
                vim.api.nvim_win_set_buf(win, alt)
            elseif
                pcall(vim.cmd, 'bprevious')
                and buf ~= vim.api.nvim_win_get_buf(win)
            then
                return
            else
                vim.api.nvim_win_set_buf(
                    win,
                    vim.api.nvim_create_buf(true, false)
                )
            end
        end)
    end

    local ok, err = pcall(vim.cmd, ('%s! %d'):format(cmd, buf))
    if
        not ok
        and not (err:find('E516%D') or err:find('E517%D') or err:find('E11%D'))
    then
        vim.notify(err, vim.log.levels.ERROR)
    end
end
