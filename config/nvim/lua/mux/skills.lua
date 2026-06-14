-- mux.skills: view-scoped drivers behind the nvim-{commit,pr,edit,changes}
-- skills. Each runs its editor work in the destination view's window via
-- mux.in_view (never touching the user's focused tab) and returns a plain
-- table

local mux = require('mux')

local M = {}

---@param buf integer
---@param lines string[]
---@param stop_pat string
local function set_head(buf, lines, stop_pat)
    if not (buf and buf > 0 and vim.api.nvim_buf_is_valid(buf)) then
        return false
    end
    local cur = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cut = #cur
    for i = 1, #cur do
        if cur[i]:match(stop_pat) then
            cut = i - 1
            break
        end
    end
    local head = {}
    for _, l in ipairs(lines) do
        head[#head + 1] = l
    end
    head[#head + 1] = ''
    vim.api.nvim_buf_set_lines(buf, 0, cut, false, head)
    for _, w in ipairs(vim.fn.win_findbuf(buf)) do
        pcall(vim.api.nvim_win_set_cursor, w, { 1, 0 })
    end
    return true
end

---@param ms integer
---@param cond fun(): boolean
---@return boolean
local function wait_for(ms, cond)
    local ok = vim.wait(ms, cond, 50)
    return ok == true
end

---@param p { message: string[], view?: any }
function M.commit(p)
    local message = p.message or {}
    if #message == 0 then
        return { ok = false, error = 'empty commit message' }
    end
    local _, err = mux.in_view(p.view or 'vcs', function()
        local b = vim.fn.bufnr('COMMIT_EDITMSG')
        if b > 0 then
            pcall(vim.cmd, 'silent! bwipeout! ' .. b)
        end
        pcall(vim.cmd, 'silent! Git')
        pcall(vim.cmd, 'silent! only')
        pcall(vim.cmd, 'Git commit')
    end)
    if err then
        return { ok = false, error = err }
    end
    local ready = wait_for(6000, function()
        local b = vim.fn.bufnr('COMMIT_EDITMSG')
        return b > 0
            and vim.fn.bufloaded(b) == 1
            and vim.bo[b].modifiable == true
    end)
    if not ready then
        return { ok = false, error = 'commit buffer did not open' }
    end
    local buf = vim.fn.bufnr('COMMIT_EDITMSG')
    if not set_head(buf, message, '^#') then
        return { ok = false, error = 'failed to write commit message' }
    end
    return { ok = true, subject = message[1] }
end

local function pr_exists()
    local ok, f = pcall(require, 'forge')
    if not ok then
        return false
    end
    local d = f.detect()
    if not d then
        return false
    end
    local pr, e = f.current_pr({ forge = d })
    if e then
        return false
    end
    return type(pr) == 'table' and pr.num ~= nil
end

---Name of the live PR compose buffer with content, or '' if not ready.
local function pr_compose_name()
    for _, b in ipairs(vim.fn.getbufinfo()) do
        local n = b.name or ''
        if
            n:find('/pr/', 1, true)
            and vim.api.nvim_buf_is_valid(b.bufnr)
            and vim.bo[b.bufnr].filetype == 'forgecompose'
            and #vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false) > 1
        then
            return n, b.bufnr
        end
    end
    return '', nil
end

---@param p { title?: string, body: string[], view?: any }
function M.pr(p)
    local body = p.body or {}
    local spec = p.view or 'vcs'
    local vcs_win, rerr = mux.resolve_view(spec)
    if not vcs_win then
        return { ok = false, error = rerr }
    end

    -- forge opens an existing PR's edit compose asynchronously (it fetches the
    -- PR over the network), so by the time the compose buffer appears the
    -- synchronous in_view window context has unwound and forge edits it into
    -- whatever window is focused, often the user's. Snapshot the layout so the
    -- compose can be parked in the vcs view and any clobbered window restored.
    local prev_buf = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        prev_buf[w] = vim.api.nvim_win_get_buf(w)
    end
    local home_win = vim.api.nvim_get_current_win()

    -- Show the compose in the vcs view and undo any pre-existing window forge
    -- replaced with it. Never closes windows or moves focus.
    local function place_compose(b)
        if not (b and vim.api.nvim_buf_is_valid(b)) then
            return
        end
        if vim.api.nvim_win_is_valid(vcs_win) then
            pcall(vim.api.nvim_win_set_buf, vcs_win, b)
        end
        for w, pb in pairs(prev_buf) do
            if
                w ~= vcs_win
                and vim.api.nvim_win_is_valid(w)
                and vim.api.nvim_win_get_buf(w) == b
                and pb ~= b
                and vim.api.nvim_buf_is_valid(pb)
            then
                pcall(vim.api.nvim_win_set_buf, w, pb)
            end
        end
    end

    local au = vim.api.nvim_create_autocmd('FileType', {
        pattern = 'forgecompose',
        callback = function(args)
            if vim.api.nvim_buf_get_name(args.buf):find('/pr/', 1, true) then
                place_compose(args.buf)
            end
        end,
    })

    local _, err = mux.in_view(spec, function()
        for _, b in ipairs(vim.fn.getbufinfo()) do
            local n = b.name or ''
            if
                n:find('/pr/', 1, true)
                and vim.bo[b.bufnr].filetype == 'forgecompose'
            then
                pcall(vim.cmd, 'silent! bwipeout! ' .. b.bufnr)
            end
        end
        pcall(vim.cmd, 'silent! Git')
        pcall(vim.cmd, 'silent! only')
        pcall(vim.cmd, 'silent! Forge pr create draft')
    end)
    if err then
        pcall(vim.api.nvim_del_autocmd, au)
        return { ok = false, error = err }
    end

    if pr_exists() then
        mux.in_view(spec, function()
            pcall(vim.cmd, 'silent! Forge pr edit')
        end)
    end

    local ready = wait_for(8000, function()
        local n = pr_compose_name()
        return n ~= ''
    end)
    pcall(vim.api.nvim_del_autocmd, au)
    if not ready then
        return {
            ok = false,
            error = 'no PR compose opened (no forge, detached HEAD, or no commits)',
        }
    end

    local name, buf = pr_compose_name()
    -- Final reconciliation if the compose landed (or was re-focused) after the
    -- autocmd ran, then restore the user's focus.
    place_compose(buf)
    if vim.api.nvim_win_is_valid(home_win) then
        pcall(vim.api.nvim_set_current_win, home_win)
    end
    if name:match('/pr/new$') then
        if p.title and p.title ~= '' then
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# ' .. p.title })
        end
        set_head(buf, body, '^%s*<!%-%-')
        return { ok = true, mode = 'create' }
    end
    local num = name:match('/pr/(%d+)/edit')
    -- existing PR: only fill an empty description
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cut = #lines
    for i = 1, #lines do
        if lines[i]:match('^%s*<!%-%-') then
            cut = i - 1
            break
        end
    end
    local empty = true
    for i = 3, cut do
        if vim.trim(lines[i]) ~= '' then
            empty = false
            break
        end
    end
    if empty then
        set_head(buf, body, '^%s*<!%-%-')
        return { ok = true, mode = 'edit_filled', num = num }
    end
    return { ok = true, mode = 'edit_kept', num = num }
end

---@param p { files: string[], items?: table[], root?: string, view?: any }
function M.edit(p)
    local files = p.files or {}
    local items = p.items or {}
    local _, err = mux.in_view(p.view or 'edit', function()
        pcall(vim.fn.setreg, '/', '')
        pcall(vim.fn.histdel, 'search')
        pcall(vim.cmd, 'silent! nohlsearch')
        pcall(vim.cmd, 'silent! only')
        if #files == 0 then
            vim.cmd('edit ' .. vim.fn.fnameescape(p.root or vim.fn.getcwd()))
        else
            vim.cmd('%argdelete')
            vim.cmd(
                'args '
                    .. table.concat(vim.tbl_map(vim.fn.fnameescape, files), ' ')
            )
            vim.cmd('edit ' .. vim.fn.fnameescape(files[1]))
            for i = 2, #files do
                vim.cmd('badd ' .. vim.fn.fnameescape(files[i]))
            end
        end
        vim.fn.setqflist({}, 'r', { title = 'edit', items = items })
        if #items > 1 then
            vim.cmd('botright copen')
            vim.cmd('wincmd p')
        else
            vim.cmd('cclose')
        end
        pcall(vim.cmd, 'silent! nohlsearch')
        vim.cmd('redraw!')
    end)
    if err then
        return { ok = false, error = err }
    end
    return { ok = true, count = #files }
end

---@param p { base: string, files: string[], items?: table[], root?: string, layout?: "unified"|"stacked"|"split" }
function M.review(p)
    local base = p.base
    if not base or base == '' then
        return { ok = false, error = 'review: missing base' }
    end
    local layout = p.layout
    if layout ~= 'unified' and layout ~= 'stacked' and layout ~= 'split' then
        layout = 'unified'
    end
    local _, verr = mux.in_view('vcs', function()
        pcall(vim.cmd, 'silent! Diff review ++layout=' .. layout .. ' ' .. base)
        if layout ~= 'split' then
            pcall(vim.cmd, 'silent! only')
        end
    end)
    if verr then
        return { ok = false, error = verr }
    end
    local res = M.edit({
        files = p.files or {},
        items = p.items or {},
        root = p.root,
        view = 'edit',
    })
    if not res.ok then
        return res
    end
    return { ok = true, count = #(p.files or {}) }
end

local ops = {
    commit = M.commit,
    pr = M.pr,
    edit = M.edit,
    review = M.review,
}

---Entry point for the CLI helpers
---@param payload table
---@return string
function M.rpc(payload)
    payload = payload or {}
    local fn = ops[payload.op]
    if not fn then
        return vim.json.encode({
            ok = false,
            error = 'unknown op: ' .. tostring(payload.op),
        })
    end
    local ok, res = pcall(fn, payload)
    if not ok then
        return vim.json.encode({ ok = false, error = tostring(res) })
    end
    return vim.json.encode(res)
end

return M
