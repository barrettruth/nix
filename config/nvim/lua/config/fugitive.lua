-- NOTE: Consider refactoring if https://github.com/neovim/neovim/issues/41745 is ever merged.

local uv = vim.uv
local watch = vim._watch

local M = {}

local debounce_ms = 100
---@type table<integer, fun()[]> bufnr -> cancel functions
local watchers = {}
---@type table<integer, uv.uv_timer_t> bufnr -> debounce timer
local timers = {}

local exclude_pattern = vim.glob.to_lpeg('**/.git/{objects,subtree-cache}/**')
    + vim.glob.to_lpeg('**/node_modules/*/**')

local watch_directory = vim.fn.has('mac') == 1
        and function(path, callback)
            return watch.watch(path, {
                exclude_pattern = exclude_pattern,
                uvflags = { recursive = true },
            }, callback)
        end
    or function(path, callback)
        return watch.watchdirs(path, {
            debounce = debounce_ms,
            exclude_pattern = exclude_pattern,
        }, callback)
    end

---@param buf integer
---@return boolean
local function buf_autoread(buf)
    local local_value = vim.bo[buf].autoread
    if local_value ~= nil then
        return local_value
    end
    return vim.go.autoread
end

---@param buf integer
---@return string[]
local function roots(buf)
    local paths = {
        vim.fn.FugitiveWorkTree(buf),
        vim.fn.FugitiveCommonDir(buf),
    }

    local candidates = {}
    for _, path in ipairs(paths) do
        if type(path) == 'string' and path ~= '' then
            path = uv.fs_realpath(path) or vim.fs.normalize(path)
            if (uv.fs_stat(path) or {}).type == 'directory' then
                candidates[path] = true
            end
        end
    end

    paths = vim.tbl_keys(candidates)
    table.sort(paths, function(a, b)
        return #a < #b
    end)

    local result = {}
    for _, path in ipairs(paths) do
        local covered = false
        for _, root in ipairs(result) do
            if vim.fs.relpath(root, path) ~= nil then
                covered = true
                break
            end
        end
        if not covered then
            result[#result + 1] = path
        end
    end
    return result
end

---@param buf integer
---@return string[]?
local function watch_roots(buf)
    if
        not vim.api.nvim_buf_is_loaded(buf)
        or vim.bo[buf].buftype ~= 'nowrite'
        or vim.b[buf].fugitive_type ~= 'index'
        or not buf_autoread(buf)
    then
        return
    end

    local result = roots(buf)
    return #result > 0 and result or nil
end

---@param buf integer
local function stop_watcher(buf)
    local cancels = watchers[buf]
    watchers[buf] = nil
    if cancels then
        for _, cancel in ipairs(cancels) do
            cancel()
        end
    end

    local timer = timers[buf]
    timers[buf] = nil
    if timer then
        timer:stop()
        timer:close()
    end
end

local ensure_watcher

---@param buf integer
ensure_watcher = function(buf)
    stop_watcher(buf)

    local paths = watch_roots(buf)
    if not paths then
        return
    end

    local timer = assert(uv.new_timer())
    local cancels = {}
    timers[buf] = timer
    watchers[buf] = cancels

    local function on_change()
        if watchers[buf] ~= cancels then
            return
        end
        timer:start(debounce_ms, 0, function()
            vim.schedule(function()
                if watchers[buf] ~= cancels then
                    return
                end
                if not watch_roots(buf) then
                    stop_watcher(buf)
                    return
                end

                local ok, err = pcall(vim.fn.FugitiveDidChange, buf)
                if not ok then
                    vim.api.nvim_echo({
                        {
                            ('fugitive: refresh failed for buffer %d: %s'):format(
                                buf,
                                err
                            ),
                        },
                    }, true, { err = true })
                end
            end)
        end)
    end

    for _, path in ipairs(paths) do
        cancels[#cancels + 1] = watch_directory(path, on_change)
    end
end

function M.setup()
    local group = vim.api.nvim_create_augroup('FugitiveAutoread', {
        clear = true,
    })

    vim.api.nvim_create_autocmd('User', {
        group = group,
        pattern = 'FugitiveIndex',
        callback = function(args)
            ensure_watcher(args.buf)
        end,
    })
    vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
        group = group,
        callback = function(args)
            stop_watcher(args.buf)
        end,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            for buf in pairs(watchers) do
                stop_watcher(buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd('OptionSet', {
        group = group,
        pattern = 'autoread',
        callback = function()
            if vim.v.option_type == 'global' then
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    ensure_watcher(buf)
                end
            else
                ensure_watcher(vim.api.nvim_get_current_buf())
            end
        end,
    })

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        ensure_watcher(buf)
    end
end

return M
