vim.keymap.set('n', '<leader>t', function()
    if vim.fn.executable('sioyek') ~= 1 then
        return vim.notify('sioyek not found', vim.log.levels.ERROR)
    end
    if vim.fn.executable('hyprctl') ~= 1 then
        return vim.notify('hyprctl not found', vim.log.levels.ERROR)
    end
    local pdf = vim.fn.expand('%:p:r') .. '.pdf'
    local basename = vim.fn.fnamemodify(pdf, ':t')
    local ret = vim.system({ 'hyprctl', 'clients', '-j' }):wait()
    if ret.code == 0 then
        for _, c in ipairs(vim.json.decode(ret.stdout)) do
            if (c.class or ''):lower():find('sioyek')
                and (c.title or ''):find(basename, 1, true) then
                vim.system({ 'hyprctl', 'dispatch', 'closewindow', 'address:' .. c.address })
                return
            end
        end
    end
    vim.system({ 'sioyek', pdf })
end, { buffer = true })
