---@type config.completion.Provider
local M = {
    source = 'files',
}

local loader = require('config.completion.loader')
local util = require('config.completion.util')

local MAX_ITEMS = 300
local TOKEN_CHAR = '[%w%-%./_~]'

---@class config.completion.files.Root
---@field root string
---@field is_git boolean

---@type table<string, config.completion.files.Root>
local dir_root = {}

---@type table<integer, config.completion.files.Root>
local buf_root = {}

---@type table<string, { files: string[]? }>
local state = {}

---@type table<string, config.completion.Loader>
local loaders = {}

---@param bufnr integer
---@return string
local function buffer_dir(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' or name:match('^%w[%w+.-]*://') then
        return vim.uv.cwd() or '.'
    end
    return vim.fn.fnamemodify(name, ':p:h')
end

---Blocking; only call from a normal (non-textlock) context such as warmup.
---@param bufnr integer
---@return config.completion.files.Root
local function resolve_root(bufnr)
    local dir = buffer_dir(bufnr)
    local cached = dir_root[dir]
    if cached then
        return cached
    end

    local git = util.git_root(dir)
    local resolved
    if git ~= '' then
        resolved = { root = git, is_git = true }
    else
        resolved = { root = vim.uv.cwd() or '.', is_git = false }
    end

    dir_root[dir] = resolved
    return resolved
end

---@param info config.completion.files.Root
---@return string[]? command, string? cwd
local function list_command(info)
    if info.is_git then
        return {
            'git',
            '-C',
            info.root,
            'ls-files',
            '--cached',
            '--others',
            '--exclude-standard',
        }
    end
    if util.executable('fd') then
        return {
            'fd',
            '--type',
            'f',
            '--strip-cwd-prefix',
            '--color',
            'never',
            '--exclude',
            '.git',
        },
            info.root
    end
    if util.executable('rg') then
        return { 'rg', '--files', '--color', 'never' }, info.root
    end
    return nil
end

---@param info config.completion.files.Root
---@return config.completion.LoaderTask
local function make_task(info)
    local command, cwd = list_command(info)

    ---@return table
    local function opts()
        local o = { text = true }
        if cwd then
            o.cwd = cwd
        end
        return o
    end

    return {
        sync = function()
            if not command then
                return ''
            end
            return vim.system(command, opts()):wait().stdout or ''
        end,
        async = function(done)
            if not command then
                done('')
                return
            end
            vim.system(command, opts(), function(result)
                done(result.stdout or '')
            end)
        end,
    }
end

---@param out string
---@return string[]
local function parse(out)
    local files = {}
    for line in (out .. '\n'):gmatch('(.-)\n') do
        if line ~= '' then
            files[#files + 1] = line
        end
    end
    return files
end

---@param info config.completion.files.Root
---@return config.completion.Loader
local function get_loader(info)
    local existing = loaders[info.root]
    if existing then
        return existing
    end

    state[info.root] = state[info.root] or {}

    local instance = loader.new({
        loaded = function()
            return state[info.root].files ~= nil
        end,
        store = function(outputs)
            state[info.root].files = parse(outputs[1] or '')
        end,
        tasks = { make_task(info) },
        wait_timeout = 200,
    })

    loaders[info.root] = instance
    return instance
end

---@param root string
---@return boolean
local function is_loaded(root)
    return state[root] ~= nil and state[root].files ~= nil
end

---@return integer startcol, string base
local function token_before_cursor()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local before = vim.api.nvim_get_current_line():sub(1, col)

    local start = col + 1
    for i = #before, 1, -1 do
        if before:sub(i, i):match(TOKEN_CHAR) then
            start = i
        else
            break
        end
    end

    return start, before:sub(start)
end

---@param bufnr? integer
function M.warmup(bufnr)
    bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    if vim.bo[bufnr].buftype ~= '' then
        return
    end

    local info = resolve_root(bufnr)
    buf_root[bufnr] = info
    get_loader(info).preload()
end

function M.reset()
    dir_root = {}
    buf_root = {}
    state = {}
    loaders = {}
end

---Feed builtin file-name completion (`i_CTRL-X_CTRL-F`) as a graceful
---fallback while the project index is still warming or has no matches.
local function feed_builtin_file()
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes('<c-x><c-f>', true, false, true),
        'n',
        false
    )
end

---Drive completion. Must be invoked through `i_CTRL-R_=` (see the `<c-f>`
---mapping) so |complete()| runs outside of mapping textlock. Shows our fuzzy
---popup, or falls back to builtin file completion while the index warms or
---when nothing matches. Always returns `''` so nothing is inserted by `<c-r>=`.
---@return string
function M.trigger()
    local bufnr = vim.api.nvim_get_current_buf()
    local info = buf_root[bufnr]

    if not info or not is_loaded(info.root) then
        vim.schedule(function()
            M.warmup(bufnr)
        end)
        feed_builtin_file()
        return ''
    end

    local files = state[info.root].files or {}
    local startcol, base = token_before_cursor()
    local matches = base ~= '' and vim.fn.matchfuzzy(files, base) or files

    local items = {}
    for i = 1, math.min(#matches, MAX_ITEMS) do
        local path = matches[i]
        items[i] = {
            word = path,
            abbr = path,
            kind = 'file',
            equal = 1,
            dup = 1,
            user_data = { source = M.source },
        }
    end

    if #items == 0 then
        feed_builtin_file()
        return ''
    end

    vim.fn.complete(startcol, items)
    return ''
end

local group = vim.api.nvim_create_augroup('ACompletionFiles', { clear = true })

vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(ev)
        M.warmup(ev.buf)
    end,
})

vim.api.nvim_create_autocmd('DirChanged', {
    group = group,
    callback = function()
        M.reset()
        M.warmup(0)
    end,
})

return M
