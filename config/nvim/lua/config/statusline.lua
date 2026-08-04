local M = {}

local jj_template = 'change_id.short(8) ++ if(conflict, " ×")'

---@type string
local jj_label = ''
---@type boolean
local in_jj = false
---@type boolean
local jj_pending = false

---@param text string
---@return string
local function segment(text)
    if text == '' then
        return ''
    end
    return ('%%#Comment#%s%%* '):format((text:gsub('%%', '%%%%')))
end

---@return string?
local function jj_root()
    local name = vim.api.nvim_buf_get_name(0)
    return vim.fs.root(name ~= '' and name or vim.fn.getcwd(), '.jj')
end

---@return nil
local function refresh_jj()
    local root = jj_root()
    in_jj = root ~= nil
    if not root then
        jj_label = ''
        return
    end
    if jj_pending then
        return
    end
    jj_pending = true
    vim.system({
        'jj',
        'log',
        '--ignore-working-copy',
        '--no-graph',
        '-r',
        '@',
        '-T',
        jj_template,
    }, { cwd = root, text = true }, function(out)
        vim.schedule(function()
            jj_pending = false
            local label = out.code == 0 and vim.trim(out.stdout) or ''
            if label ~= jj_label then
                jj_label = label
                vim.cmd.redrawstatus()
            end
        end)
    end)
end

---@return string
local function branch()
    if in_jj then
        return segment(jj_label)
    end
    local ok, head = pcall(vim.fn.FugitiveHead, 7)
    if not ok or head == '' then
        return ''
    end
    return segment(head)
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

---@return nil
function M.setup()
    vim.o.statusline = "%!v:lua.require'config.statusline'.render()"

    local aug = vim.api.nvim_create_augroup('StatusLine', { clear = true })

    vim.api.nvim_create_autocmd({ 'BufEnter', 'DirChanged', 'FocusGained' }, {
        group = aug,
        callback = refresh_jj,
    })

    refresh_jj()
end

return M
