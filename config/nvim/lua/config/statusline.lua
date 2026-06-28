local M = {}

function M.render()
    local name = vim.fn.expand('%')
    local path = name ~= ''
            and ('%%#Directory#%s%%* '):format(vim.fn.expand('%:~'))
        or ''
    local buftype = vim.bo.buftype
    local flags = buftype == 'terminal' and '%h%r' or '%h%m%r'
    local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or buftype
    return (' %s%s%%=%%c:%%l/%%L %s '):format(path, flags, filetype)
end

return M
