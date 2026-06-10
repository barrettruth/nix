---@type config.completion.Provider
local M = {
    source = 'git_log',
}

local async = require('config.completion.async')
local cache = require('config.completion.forge.cache')
local git = require('config.completion.forge.git')

local BUCKET_LOG = 'log'
local STRONG_MIN = 1
local LOOSE_MIN = 4

local STRONG_PREFIXES = {
    '^%s*[Ff]ixes:%s+$',
    '^%s*[Rr]everts:%s+$',
    '^%s*[Rr]efs:%s+$',
    '^%s*[Ss]ee:%s+$',
    '^%s*[Cc]herry%-picked from%s+$',
    '%(cherry picked from commit%s+$',
}

local lifecycle = async.new_lifecycle()
local kick_resolve

---@param bufnr integer
---@return string
local function buffer_dir(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' then
        return vim.uv.cwd() or '.'
    end
    return vim.fn.fnamemodify(name, ':p:h')
end

---@param bufnr integer
---@return string
local function repo_root(bufnr)
    return git.git_root(buffer_dir(bufnr))
end

---@param before string
---@return boolean
local function strong_context(before)
    for _, pat in ipairs(STRONG_PREFIXES) do
        if before:match(pat) then
            return true
        end
    end
    return false
end

---@param ctx config.completion.Context
---@return config.completion.git_log.TokenContext?
local function token_at_cursor(ctx)
    if ctx.filetype == 'gitcommit' and ctx.row == 1 then
        return nil
    end

    local before = ctx.before
    local token_start = #before + 1
    for i = #before, 1, -1 do
        local c = before:sub(i, i)
        if c:match('[0-9a-fA-F]') then
            token_start = i
        else
            break
        end
    end

    local base = before:sub(token_start)
    if base == '' and not strong_context(before) then
        return nil
    end

    local prev_char = token_start > 1
            and before:sub(token_start - 1, token_start - 1)
        or ''
    if prev_char ~= '' and not prev_char:match('[%s%(%[]') then
        return nil
    end

    local strong = strong_context(before:sub(1, token_start - 1))
    local min = strong and STRONG_MIN or LOOSE_MIN
    if #base == 0 and not strong then
        return nil
    end
    if #base > 0 and #base < min then
        return nil
    end

    return {
        bufnr = ctx.bufnr,
        row = ctx.row,
        start_col = token_start - 1,
        end_col = ctx.col,
        base = base,
        strong_context = strong,
    }
end

---@param ctx config.completion.Context
---@return config.completion.git_log.TokenContext?
function M.context_at_cursor(ctx)
    return token_at_cursor(ctx)
end

---@param commit config.completion.git_log.Commit
---@param root string
---@return config.completion.Item
local function commit_to_item(commit, root)
    local subject = commit.subject ~= '' and (' ' .. commit.subject) or ''
    local abbr = commit.short .. subject
    if #abbr > 79 then
        abbr = abbr:sub(1, 76) .. '...'
    end
    return {
        word = commit.short,
        abbr = abbr,
        kind = 'commit',
        info = '',
        user_data = {
            source = M.source,
            git_log = { root = root, sha = commit.sha },
        },
    }
end

---@param commits config.completion.git_log.Commit[]
---@param tc config.completion.git_log.TokenContext
---@param root string
---@return config.completion.Items
local function build_items(commits, tc, root)
    local base = tc.base:lower()
    local out = {}
    if base == '' then
        for _, c in ipairs(commits) do
            out[#out + 1] = commit_to_item(c, root)
        end
        return out
    end
    for _, c in ipairs(commits) do
        if
            c.short:lower():find('^' .. base) or c.sha:lower():find('^' .. base)
        then
            out[#out + 1] = commit_to_item(c, root)
        end
    end
    return out
end

---@param root string
local function kick_log(root)
    if
        cache.is_ready(root, BUCKET_LOG) or cache.is_loading(root, BUCKET_LOG)
    then
        return
    end
    cache.mark_loading(root, BUCKET_LOG)
    git.fetch_log(root, function(items, err)
        if err then
            cache.set_error(root, BUCKET_LOG, err)
        else
            cache.set_ready(root, BUCKET_LOG, items or {})
        end
        M._try_inject_pending()
    end)
end

---@param p table
---@return config.completion.Items?
local function inject_check(p)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, cursor[2])
    local typed = before:sub(p.start_col + 1)
    if typed:find('[^0-9a-fA-F]') then
        return nil
    end
    local ctx = {
        base = typed,
        before = before,
        bufnr = p.bufnr,
        col = cursor[2],
        filetype = vim.bo[p.bufnr].filetype,
        line = line,
        row = cursor[1],
    }
    local tc = token_at_cursor(ctx)
    if not tc or tc.start_col ~= p.start_col then
        return nil
    end
    if not cache.is_ready(p.root, BUCKET_LOG) then
        return nil
    end
    local b = cache.get(p.root, BUCKET_LOG)
    if not b or not b.items then
        return nil
    end
    return build_items(b.items, tc, p.root)
end

function M._try_inject_pending()
    lifecycle.try_inject(inject_check)
end

---@param ctx config.completion.Context
---@return integer?
function M.findstart(ctx)
    local tc = token_at_cursor(ctx)
    if not tc then
        return nil
    end
    return tc.start_col
end

---@param ctx config.completion.Context
---@return config.completion.Items
function M.complete(ctx)
    local tc = token_at_cursor(ctx)
    if not tc then
        return {}
    end
    local root = repo_root(ctx.bufnr)
    if root == '' then
        return {}
    end

    if cache.is_ready(root, BUCKET_LOG) then
        local b = cache.get(root, BUCKET_LOG)
        if b and b.items then
            local items = build_items(b.items, tc, root)
            if #items > 0 or #tc.base < 7 then
                return items
            end
            kick_resolve(root, tc.base)
            return items
        end
    end

    lifecycle.set({
        bufnr = tc.bufnr,
        row = tc.row,
        start_col = tc.start_col,
        root = root,
    })
    if not cache.is_loading(root, BUCKET_LOG) then
        kick_log(root)
    else
        cache.add_waiter(root, BUCKET_LOG, function()
            M._try_inject_pending()
        end)
    end
    return {}
end

---@param root string
---@param sha string
kick_resolve = function(root, sha)
    local key = 'resolve:' .. sha:lower()
    if cache.is_loading(root, key) or cache.is_ready(root, key) then
        return
    end
    cache.mark_loading(root, key)
    git.resolve(root, sha, function(commit, err)
        if err or not commit then
            cache.set_error(root, key, err or 'missing')
            return
        end
        local b = cache.get(root, BUCKET_LOG)
        if b and type(b.items) == 'table' then
            for _, c in ipairs(b.items) do
                if c.sha == commit.sha then
                    cache.set_ready(root, key, true)
                    return
                end
            end
            table.insert(b.items, 1, commit)
        end
        cache.set_ready(root, key, true)
        M._try_inject_pending()
    end)
end

---@param bufnr integer
function M.warmup(bufnr)
    bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
    local root = repo_root(bufnr)
    if root == '' then
        return
    end
    if
        not cache.is_ready(root, BUCKET_LOG)
        and not cache.is_loading(root, BUCKET_LOG)
    then
        kick_log(root)
    end
end

---@param selected integer
---@param item config.completion.Item
local function fill_doc(selected, item)
    local data = vim.tbl_get(item, 'user_data', 'git_log')
    if type(data) ~= 'table' then
        return
    end
    local doc_bucket = 'doc:' .. data.sha
    local b = cache.get(data.root, doc_bucket)
    if b and b.state == 'ready' then
        local body = b.items
        if
            type(body) == 'string'
            and body ~= ''
            and vim.api.nvim__complete_set
        then
            vim.api.nvim__complete_set(selected, { info = body })
        end
        return
    end
    if b and b.state == 'loading' then
        return
    end
    cache.mark_loading(data.root, doc_bucket)
    git.fetch_show(data.root, data.sha, function(body, err)
        if err or not body then
            cache.set_error(data.root, doc_bucket, err or 'missing')
            return
        end
        cache.set_ready(data.root, doc_bucket, body)
        local info = vim.fn.complete_info({ 'selected', 'items' })
        local current_selected = info.selected
        if current_selected ~= selected then
            return
        end
        local items = info.items or {}
        local cur = items[current_selected + 1]
        local cur_data = cur and vim.tbl_get(cur, 'user_data', 'git_log')
        if
            not cur_data
            or cur_data.sha ~= data.sha
            or cur_data.root ~= data.root
        then
            return
        end
        if vim.api.nvim__complete_set and body ~= '' then
            vim.api.nvim__complete_set(selected, { info = body })
        end
    end)
end

async.register_doc_handler(M.source, fill_doc)

---@param findstart integer
---@param base string
---@return integer|config.completion.Items
function M.complete_omnifunc(findstart, base)
    local ctx = require('config.completion.util').context(base)
    if findstart == 1 then
        return M.findstart(ctx) or -2
    end
    return M.complete(ctx)
end

return M
