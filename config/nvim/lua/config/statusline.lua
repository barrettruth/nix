local M = {}

---@return string
local function branch()
    local ok, head = pcall(vim.fn.FugitiveHead, 7)
    if not ok or head == '' then
        return ''
    end
    return ('%%#Comment#%s%%* '):format((head:gsub('%%', '%%%%')))
end

---@return string
local function recording()
    if vim.o.cmdheight ~= 0 or vim.o.shortmess:find('q', 1, true) then
        return ''
    end
    local register = vim.fn.reg_recording()
    if register == '' then
        return ''
    end
    return ('%%#ModeMsg#recording @%s%%* '):format(register)
end

---@return string
local function search_count()
    if vim.o.cmdheight ~= 0 then
        return ''
    end
    local ok, count = pcall(vim.fn.searchcount, { maxcount = 999 })
    if
        not ok
        or type(count) ~= 'table'
        or not count.total
        or count.total == 0
    then
        return ''
    end
    return ('[%s/%s] '):format(count.current, count.total)
end

---@return string
function M.render()
    local path = branch()
    local name = vim.fn.expand('%')
    if name ~= '' then
        path = path
            .. ('%%#Directory#%s%%* '):format(
                vim.fn.expand('%:~'):gsub('%%', '%%%%')
            )
    end
    local buftype = vim.bo.buftype
    local flags = buftype == 'terminal' and '%h%r' or '%h%m%r'
    local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or buftype
    return (' %s%s%%=%s%s%%c:%%l/%%L %s '):format(
        path,
        flags,
        recording(),
        search_count(),
        filetype
    )
end

return M
