---@type config.completion.Provider
local M = {
    source = 'forge_refs',
}

local async = require('config.completion.async')
local cache = require('config.completion.forge.cache')
local context = require('config.completion.forge.context')
local notify = require('config.completion.forge.notify')
local registry = require('config.completion.forge.registry')

local PR_GLYPH = '\239\144\135'
local ISSUE_GLYPH = '\239\144\159'

---@type table<string, true>
local TRIGGER_CHARS = { ['#'] = true, ['@'] = true, ['!'] = true }

local lifecycle = async.new_lifecycle()
local kick_exact

---@param tc {cross_repo?: {owner: string, repo: string}, bufnr: integer}
---@return config.completion.forge.Repo?
local function resolve_repo(tc)
    if tc.cross_repo then
        return context.cross_repo(
            tc.bufnr,
            tc.cross_repo.owner,
            tc.cross_repo.repo
        )
    end
    return context.derive(tc.bufnr)
end

---@param ctx config.completion.Context
---@return config.completion.forge.TokenContext?
local function token_at_cursor(ctx)
    local before = ctx.before
    local trigger_col, trigger
    for i = #before, 1, -1 do
        local c = before:sub(i, i)
        if TRIGGER_CHARS[c] then
            trigger_col = i
            trigger = c
            break
        end
        if not c:match('[%w%-./_]') then
            break
        end
    end
    if not trigger_col or not trigger then
        return nil
    end

    local prev = trigger_col > 1
            and before:sub(trigger_col - 1, trigger_col - 1)
        or ''
    if prev:match('[%w_]') and prev ~= '/' then
        if
            not (
                trigger == '#'
                and before:sub(1, trigger_col - 1):match('[%w%-_.]+/[%w%-_.]+$')
            )
        then
            return nil
        end
    end

    local base = before:sub(trigger_col + 1)
    if base:find('[^%w%-./_]') then
        return nil
    end

    local cross_repo
    local pre = before:sub(1, trigger_col - 1)
    local cr_owner, cr_repo = pre:match('([%w%-_.]+)/([%w%-_.]+)$')
    if cr_owner and cr_repo then
        local pre_idx = #pre - #cr_owner - 1 - #cr_repo
        local before_pre = pre_idx > 0 and pre:sub(pre_idx, pre_idx) or ''
        if not before_pre:match('[%w_/]') then
            cross_repo = { owner = cr_owner, repo = cr_repo }
        end
    end

    local tc = {
        bufnr = ctx.bufnr,
        row = ctx.row,
        start_col = trigger_col - 1,
        end_col = ctx.col,
        trigger = trigger,
        base = base,
        cross_repo = cross_repo,
    }

    local repo = resolve_repo(tc)
    if not repo then
        return nil
    end
    local backend = registry.get(repo.backend)
    if not backend then
        return nil
    end
    if not vim.tbl_contains(backend.triggers, trigger) then
        return nil
    end

    return tc
end

---@param ctx config.completion.Context
---@return config.completion.forge.TokenContext?
function M.context_at_cursor(ctx)
    return token_at_cursor(ctx)
end

---@param backend config.completion.forge.Backend
---@param trigger string
---@return string?
local function bucket_for(backend, trigger)
    return backend.bucket_for_trigger and backend.bucket_for_trigger[trigger]
        or nil
end

---@param item config.completion.forge.RefItem
---@param trigger string
---@param repo config.completion.forge.Repo
---@return config.completion.Item
local function ref_to_item(item, trigger, repo)
    local glyph = (item.kind == 'pr' or item.kind == 'mr') and PR_GLYPH
        or ISSUE_GLYPH
    local tags = {}
    if item.draft then
        tags[#tags + 1] = 'draft'
    end
    if item.state == 'closed' or item.state == 'merged' then
        tags[#tags + 1] = item.state
    end
    local state = #tags > 0 and (' [' .. table.concat(tags, ', ') .. ']') or ''
    local abbr = ('%s%d %s %s%s'):format(
        trigger,
        item.number,
        glyph,
        item.title,
        state
    )
    if #abbr > 79 then
        abbr = abbr:sub(1, 76) .. '...'
    end
    return {
        word = trigger .. tostring(item.number),
        abbr = abbr,
        kind = 'forge',
        info = '',
        user_data = {
            source = M.source,
            forge = {
                backend = repo.backend,
                host = repo.host,
                owner = repo.owner,
                repo = repo.repo,
                key = repo.key,
                kind = item.kind,
                number = item.number,
            },
        },
    }
end

---@param item config.completion.forge.MentionItem
---@param repo config.completion.forge.Repo
---@return config.completion.Item
local function mention_to_item(item, repo)
    return {
        word = '@' .. item.login,
        abbr = '@' .. item.login,
        kind = 'forge',
        info = '',
        user_data = {
            source = M.source,
            forge = {
                backend = repo.backend,
                host = repo.host,
                owner = repo.owner,
                repo = repo.repo,
                key = repo.key,
                kind = 'mention',
                login = item.login,
            },
        },
    }
end

---@param items config.completion.forge.RefItem[]
---@param tc config.completion.forge.TokenContext
---@param repo config.completion.forge.Repo
---@return config.completion.Items
local function filter_refs(items, tc, repo)
    local base = tc.base
    local trigger = tc.trigger
    local out = {}
    if base == '' then
        for _, it in ipairs(items) do
            out[#out + 1] = ref_to_item(it, trigger, repo)
        end
        return out
    end

    local n = tonumber(base)
    if n then
        for _, it in ipairs(items) do
            if tostring(it.number):find('^' .. base) then
                out[#out + 1] = ref_to_item(it, trigger, repo)
            end
        end
        return out
    end

    local lower = base:lower()
    for _, it in ipairs(items) do
        if it.title:lower():find(lower, 1, true) then
            out[#out + 1] = ref_to_item(it, trigger, repo)
        end
    end
    return out
end

---@param items config.completion.forge.MentionItem[]
---@param tc config.completion.forge.TokenContext
---@param repo config.completion.forge.Repo
---@return config.completion.Items
local function filter_mentions(items, tc, repo)
    local base = tc.base:lower()
    local out = {}
    for _, it in ipairs(items) do
        if base == '' or it.login:lower():find('^' .. base) then
            out[#out + 1] = mention_to_item(it, repo)
        end
    end
    return out
end

---@param tc config.completion.forge.TokenContext
---@param repo config.completion.forge.Repo
---@param bucket string
---@return config.completion.Items
local function build_items(tc, repo, bucket)
    local b = cache.get(repo.key, bucket)
    if not b or b.state ~= 'ready' or not b.items then
        return {}
    end
    if bucket == 'mentions' then
        return filter_mentions(b.items, tc, repo)
    end
    return filter_refs(b.items, tc, repo)
end

---@param backend config.completion.forge.Backend
---@param repo config.completion.forge.Repo
---@param bucket string
local function kick_fetch(backend, repo, bucket)
    if
        cache.is_loading(repo.key, bucket) or cache.is_ready(repo.key, bucket)
    then
        return
    end

    cache.mark_loading(repo.key, bucket)

    backend.fetch(bucket, repo, function(items, err)
        if err then
            cache.set_error(repo.key, bucket, err)
        else
            cache.set_ready(repo.key, bucket, items or {})
        end
        M._try_inject_pending()
    end)
end

---Re-derive context from current cursor and return items if the pending
---request still applies to what the user is doing.
---@param p table
---@return config.completion.Items?
local function inject_check(p)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, cursor[2])
    local trigger_at = before:sub(p.start_col + 1, p.start_col + 1)
    if trigger_at ~= p.trigger then
        return nil
    end
    local typed = before:sub(p.start_col + 2)
    if typed:find('[^%w%-./_]') then
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
    if not tc or tc.trigger ~= p.trigger then
        return nil
    end
    local repo = resolve_repo(tc)
    if not repo or repo.key ~= p.repo_key then
        return nil
    end
    if not cache.is_ready(repo.key, p.bucket) then
        return nil
    end
    return build_items(tc, repo, p.bucket)
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

    local repo = resolve_repo(tc)
    if not repo then
        return {}
    end

    local backend = registry.get(repo.backend)
    if not backend then
        return {}
    end

    local bucket = bucket_for(backend, tc.trigger)
    if not bucket then
        return {}
    end

    if tc.trigger == '#' or tc.trigger == '!' then
        local n = tonumber(tc.base)
        if n then
            kick_exact(backend, repo, bucket, n)
        end
    end

    if cache.is_ready(repo.key, bucket) then
        return build_items(tc, repo, bucket)
    end

    notify.note_explicit_attempt(repo.key)

    lifecycle.set({
        bufnr = tc.bufnr,
        row = tc.row,
        start_col = tc.start_col,
        trigger = tc.trigger,
        repo_key = repo.key,
        bucket = bucket,
    })

    if not cache.is_loading(repo.key, bucket) then
        kick_fetch(backend, repo, bucket)
    else
        cache.add_waiter(repo.key, bucket, function()
            M._try_inject_pending()
        end)
    end

    return {}
end

---@param repo_key string
---@param bucket string
---@param item config.completion.forge.RefItem
---@return boolean
local function merge_into_bucket(repo_key, bucket, item)
    local b = cache.get(repo_key, bucket)
    if not (b and b.state == 'ready' and type(b.items) == 'table') then
        return false
    end
    for _, ref in ipairs(b.items) do
        if ref.number == item.number then
            return true
        end
    end
    table.insert(b.items, 1, item)
    return true
end

---@param backend config.completion.forge.Backend
---@param repo config.completion.forge.Repo
---@param bucket string
---@param n integer
kick_exact = function(backend, repo, bucket, n)
    local key = bucket .. '_exact:' .. n
    if cache.is_loading(repo.key, key) or cache.is_ready(repo.key, key) then
        return
    end
    cache.mark_loading(repo.key, key)
    backend.fetch_exact(bucket, repo, n, function(item, err)
        if err or not item then
            cache.set_error(repo.key, key, err or 'missing')
            return
        end
        cache.set_ready(repo.key, key, true)
        if merge_into_bucket(repo.key, bucket, item) then
            M._try_inject_pending()
            return
        end
        cache.add_waiter(repo.key, bucket, function()
            merge_into_bucket(repo.key, bucket, item)
            M._try_inject_pending()
        end)
    end)
end

---@param bufnr integer
function M.warmup(bufnr)
    bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
    local repo = context.derive(bufnr)
    if not repo then
        return
    end
    local backend = registry.get(repo.backend)
    if not backend then
        return
    end
    for _, trigger in ipairs(backend.triggers) do
        local bucket = bucket_for(backend, trigger)
        if
            bucket
            and not cache.is_ready(repo.key, bucket)
            and not cache.is_loading(repo.key, bucket)
        then
            kick_fetch(backend, repo, bucket)
        end
    end
end

---@param data config.completion.ForgeItemData
---@return config.completion.forge.Repo
local function repo_from_item_data(data)
    return {
        backend = data.backend,
        host = data.host,
        owner = data.owner,
        repo = data.repo,
        key = data.key,
    }
end

---@param kind 'issue'|'pr'|'mr'
---@return string
local function doc_bucket_for_kind(kind)
    if kind == 'mr' then
        return 'mrs'
    end
    return 'refs'
end

---@param selected integer
---@param item config.completion.Item
local function fill_doc(selected, item)
    local data = vim.tbl_get(item, 'user_data', 'forge')
    if type(data) ~= 'table' then
        return
    end
    if data.kind ~= 'issue' and data.kind ~= 'pr' and data.kind ~= 'mr' then
        return
    end

    local bucket = doc_bucket_for_kind(data.kind)
    local doc_key = bucket .. '_doc:' .. tostring(data.number)

    local b = cache.get(data.key, doc_key)
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

    local backend = registry.get(data.backend)
    if not backend then
        return
    end
    local repo = repo_from_item_data(data)

    cache.mark_loading(data.key, doc_key)
    backend.fetch_doc(bucket, repo, data.number, function(body, err)
        if err or not body then
            cache.set_error(data.key, doc_key, err or 'missing')
            return
        end
        cache.set_ready(data.key, doc_key, body)
        local info = vim.fn.complete_info({ 'selected', 'items' })
        local current_selected = info.selected
        if current_selected ~= selected then
            return
        end
        local items = info.items or {}
        local cur = items[current_selected + 1]
        local cur_data = cur and vim.tbl_get(cur, 'user_data', 'forge')
        if
            not cur_data
            or cur_data.key ~= data.key
            or cur_data.number ~= data.number
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
