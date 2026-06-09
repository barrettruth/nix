-- mux: in-Neovim "multiplexer" brain. Each "view" is a tagged tabpage; switching
-- projects is `:connect` to another per-project nvim server (see scripts/mux).

local M = {}

-- view registry. kind: editor | terminal | task | vcs
local views = {
    edit = { key = 'e', kind = 'editor' },
    ai = {
        key = 'a',
        kind = 'terminal',
        cmd = { 'devin' },
        restore_cmd = { 'devin', '--continue' },
        lifecycle = 'ephemeral',
        restore = true,
    },
    zsh = {
        key = 'z',
        kind = 'terminal',
        cmd = { vim.o.shell },
        lifecycle = 'ephemeral',
    },
    vcs = { key = 'v', kind = 'vcs', restore = true },
    run = { key = 'r', kind = 'task', recipe = 'run', lifecycle = 'ephemeral' },
    build = {
        key = 'b',
        kind = 'task',
        recipe = 'build',
        lifecycle = 'persistent',
    },
    test = {
        key = 't',
        kind = 'task',
        recipe = 'test',
        lifecycle = 'persistent',
    },
}
M.views = views

-- stable order for keymaps, the picker header, and per-view picker actions
local VIEW_ORDER = { 'edit', 'ai', 'vcs', 'run', 'build', 'test' }

-- tabpage handle -> view name (handles are stable ids, unlike tab numbers)
local tab_view = {}

local function tag(tabpage, name)
    tab_view[tabpage] = name
end

local function prune()
    for tp in pairs(tab_view) do
        if not vim.api.nvim_tabpage_is_valid(tp) then
            tab_view[tp] = nil
        end
    end
end

local function find_view(name)
    for tp, v in pairs(tab_view) do
        if v == name and vim.api.nvim_tabpage_is_valid(tp) then
            return tp
        end
    end
    return nil
end

-- just recipe presence, cached per cwd (invalidated on DirChanged)
local recipe_cache = {}

local function has_recipe(cwd, recipe)
    local set = recipe_cache[cwd]
    if not set then
        set = {}
        local res = vim.system(
            { 'just', '--summary' },
            { text = true, cwd = cwd }
        )
            :wait()
        if res.code == 0 and res.stdout then
            for r in res.stdout:gmatch('%S+') do
                set[r] = true
            end
        end
        recipe_cache[cwd] = set
    end
    return set[recipe] == true
end

local function close_view_tab(tp)
    vim.schedule(function()
        if not vim.api.nvim_tabpage_is_valid(tp) then
            return
        end
        if #vim.api.nvim_list_tabpages() <= 1 then
            -- never close the last tab (E784); reset it to an empty edit view
            local win = vim.api.nvim_tabpage_get_win(tp)
            vim.api.nvim_win_call(win, function()
                pcall(vim.cmd, 'enew')
            end)
            tab_view[tp] = 'edit'
            return
        end
        local win = vim.api.nvim_tabpage_get_win(tp)
        vim.api.nvim_win_call(win, function()
            pcall(vim.cmd, 'tabclose')
        end)
        tab_view[tp] = nil
    end)
end

-- fill the current window/tab with a view's content. `restoring` swaps in a
-- view's restore_cmd (e.g. ai resumes with `devin --continue` rather than
-- spawning a fresh session).
local function materialize(name, restoring)
    local spec = views[name]
    local cwd = vim.fn.getcwd()
    if spec.kind == 'editor' then
        vim.cmd.edit(cwd)
    elseif spec.kind == 'vcs' then
        -- fugitive status, sole window in the tab; closing it closes the tab
        pcall(vim.cmd, 'Git')
        pcall(vim.cmd, 'only')
    elseif spec.kind == 'terminal' or spec.kind == 'task' then
        local cmd = (restoring and spec.restore_cmd)
            or spec.cmd
            or { 'just', spec.recipe }
        vim.fn.jobstart(cmd, { term = true, cwd = cwd })
        vim.cmd.startinsert()
    end
end

---@param name string
function M.open_view(name)
    local spec = views[name]
    if not spec then
        return
    end
    local existing = find_view(name)
    if existing then
        vim.api.nvim_set_current_tabpage(existing)
        return
    end

    local cwd = vim.fn.getcwd()
    if spec.kind == 'task' and not has_recipe(cwd, spec.recipe) then
        vim.notify(
            ('mux: no "%s" recipe in justfile'):format(spec.recipe),
            vim.log.levels.WARN
        )
        return
    end

    vim.cmd.tabnew()
    tag(vim.api.nvim_get_current_tabpage(), name)
    materialize(name, false)
end

local bufremove = require('config.bufremove')

function M.bufdelete()
    bufremove(false)
end

function M.bufwipe()
    bufremove(true)
end

local function show_picker(live_out, zoxide_out)
    local live = {} -- cwd -> socket
    for line in (live_out or ''):gmatch('[^\n]+') do
        local cwd, sock = line:match('^(.-)\t(.+)$')
        if cwd then
            live[cwd] = sock
        end
    end

    local here = vim.fn.getcwd()
    local seen, lines, meta = {}, {}, {}
    local function add(path)
        if not path or path == '' then
            return
        end
        path = (vim.fn.fnamemodify(path, ':p'):gsub('/$', ''))
        if seen[path] then
            return
        end
        if not live[path] and vim.uv.fs_stat(path .. '/.git') == nil then
            return
        end
        seen[path] = true
        local mark = (path == here) and '*' or (live[path] and 'o' or ' ')
        local disp = ('%s %s'):format(mark, vim.fn.fnamemodify(path, ':~'))
        lines[#lines + 1] = disp
        meta[disp] = { path = path, socket = live[path] }
    end
    for cwd in pairs(live) do
        add(cwd)
    end
    for line in (zoxide_out or ''):gmatch('[^\n]+') do
        add(line)
    end

    if #lines == 0 then
        vim.notify('mux: no projects found', vim.log.levels.WARN)
        return
    end

    local ok, fzf = pcall(require, 'fzf-lua')
    if ok then
        -- enter connects; ctrl-<key> connects AND opens that view on the project
        -- (mirrors the old tmux picker's prefix + ^a/^e/^v/... bindings). fzf-lua's
        -- native action header hardcodes the "<ctrl-x>" form, so we build the
        -- header ourselves but reuse its highlight groups so the ^X keys stay
        -- highlighted; plain-function actions keep set_header from overwriting it.
        local hl = require('fzf-lua.utils').ansi_from_hl
        local actions = {
            ['default'] = function(sel)
                if sel and sel[1] then
                    M._connect(meta[sel[1]])
                end
            end,
        }
        local parts = {}
        for _, name in ipairs(VIEW_ORDER) do
            local spec = views[name]
            actions['ctrl-' .. spec.key] = function(sel)
                if sel and sel[1] then
                    M._connect(meta[sel[1]], name)
                end
            end
            parts[#parts + 1] = ('%s to %s'):format(
                hl('FzfLuaHeaderBind', '^' .. spec.key:upper()),
                hl('FzfLuaHeaderText', name)
            )
        end
        fzf.fzf_exec(lines, {
            prompt = 'project> ',
            fzf_args = ((vim.env.FZF_DEFAULT_OPTS or '')
                :gsub('%-%-bind=ctrl%-a:select%-all', '')
                :gsub('--color=[^%s]+', '')),
            fzf_opts = {
                ['--ansi'] = true,
                ['--header'] = ':: ' .. table.concat(parts, ' | '),
            },
            actions = actions,
        })
    else
        vim.ui.select(lines, { prompt = 'mux project' }, function(choice)
            if choice then
                M._connect(meta[choice])
            end
        end)
    end
end

-- persist the last-attached project root (shared with scripts/mux record_last);
-- bare `mux` reads this to re-attach. Recorded on every in-nvim :connect.
local function record_last(root)
    if not root or root == '' then
        return
    end
    local dir = vim.fn.stdpath('state') .. '/mux'
    pcall(vim.fn.mkdir, dir, 'p')
    pcall(vim.fn.writefile, { root }, dir .. '/last')
end

---@param entry { path: string, socket: string? }
---@param view string? open this view on the target server before attaching
function M._connect(entry, view)
    if not entry then
        return
    end
    local function go(sock)
        if not sock or sock == '' then
            return
        end
        if view then
            local expr = (
                "luaeval('(function() "
                .. "require([[mux]]).open_view([[%s]]) return 1 end)()')"
            ):format(view)
            vim.system({ 'nvim', '--server', sock, '--remote-expr', expr })
                :wait()
        end
        record_last(entry.path)
        vim.cmd('connect ' .. vim.fn.fnameescape(sock))
    end
    if entry.socket and entry.socket ~= '' then
        go(entry.socket)
        return
    end
    vim.system({ 'mux', 'ensure', entry.path }, { text = true }, function(res)
        local sock = res.code == 0 and res.stdout and res.stdout:match('[^\n]+')
            or nil
        vim.schedule(function()
            if sock then
                go(sock)
            else
                vim.notify(
                    'mux: ensure failed for ' .. entry.path,
                    vim.log.levels.ERROR
                )
            end
        end)
    end)
end

function M.pick_project()
    vim.system({ 'mux', 'list' }, { text = true }, function(live_res)
        vim.system({ 'zoxide', 'query', '-l' }, { text = true }, function(z_res)
            vim.schedule(function()
                show_picker(live_res.stdout or '', z_res.stdout or '')
            end)
        end)
    end)
end

---@param step integer 1 = next live project, -1 = previous (wraps)
function M.cycle_project(step)
    vim.system({ 'mux', 'list' }, { text = true }, function(res)
        local entries = {}
        for line in (res.stdout or ''):gmatch('[^\n]+') do
            local cwd, sock = line:match('^(.-)\t(.+)$')
            if sock then
                entries[#entries + 1] = { cwd = cwd, sock = sock }
            end
        end
        vim.schedule(function()
            if #entries < 2 then
                vim.notify('mux: no other project', vim.log.levels.INFO)
                return
            end
            local cur, idx = vim.v.servername, 1
            for i, e in ipairs(entries) do
                if e.sock == cur then
                    idx = i
                    break
                end
            end
            local target = entries[((idx - 1 + step) % #entries) + 1]
            if target and target.sock ~= cur then
                record_last(target.cwd)
                vim.cmd('connect ' .. vim.fn.fnameescape(target.sock))
            end
        end)
    end)
end

local function sessions_dir()
    return vim.fn.stdpath('state') .. '/mux/sessions'
end

local function session_file()
    local slug = vim.fn.getcwd():gsub('[^%w._-]', '_')
    return sessions_dir() .. '/' .. slug .. '.vim'
end

function M.save_session()
    local map = {}
    for tp, view in pairs(tab_view) do
        if vim.api.nvim_tabpage_is_valid(tp) then
            map[tostring(vim.api.nvim_tabpage_get_number(tp))] = view
        end
    end
    vim.g.MuxViews = vim.json.encode(map)
    vim.fn.mkdir(sessions_dir(), 'p')
    pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(session_file()))
end

---@return boolean restored
function M.load_session()
    if vim.fn.argc(-1) ~= 0 then
        return false
    end
    local f = session_file()
    if vim.fn.filereadable(f) == 0 then
        return false
    end
    if not pcall(vim.cmd, 'silent! source ' .. vim.fn.fnameescape(f)) then
        return false
    end
    for k in pairs(tab_view) do
        tab_view[k] = nil
    end
    local raw = vim.g.MuxViews
    if type(raw) == 'string' and raw ~= '' then
        local okj, decoded = pcall(vim.json.decode, raw)
        if okj and type(decoded) == 'table' then
            local tabs = vim.api.nvim_list_tabpages()
            for nr, view in pairs(decoded) do
                local tp = tabs[tonumber(nr)]
                if tp and vim.api.nvim_tabpage_is_valid(tp) then
                    tab_view[tp] = view
                end
            end
        end
    end

    -- mksession restored the edit view's real state and left every other view
    -- tab as an empty skeleton. re-materialize the ones we keep (ai, vcs); drop
    -- the rest so no blank buffer lingers. preserve the focused tab.
    local cur = vim.api.nvim_get_current_tabpage()
    local drop = {}
    for tp, view in pairs(tab_view) do
        local spec = views[view]
        if
            vim.api.nvim_tabpage_is_valid(tp)
            and spec
            and spec.kind ~= 'editor'
        then
            if spec.restore then
                vim.api.nvim_set_current_tabpage(tp)
                materialize(view, true)
            else
                drop[tp] = true
            end
        end
    end
    if drop[cur] then
        cur = find_view('edit') or cur
    end
    if vim.api.nvim_tabpage_is_valid(cur) then
        vim.api.nvim_set_current_tabpage(cur)
    end
    for tp in pairs(drop) do
        close_view_tab(tp)
    end
    return true
end

function M.setup()
    if M._did then
        return
    end
    M._did = true

    -- no 'terminal': mksession must not replay terminal commands (no auto
    -- rebuild/retest, no fresh devin). load_session re-materializes the views
    -- we keep and drops the rest, so the registry owns restore policy.
    vim.o.sessionoptions =
        'buffers,curdir,folds,globals,help,tabpages,winsize,winpos'

    local prefix = '<a-x>'
    for name, spec in pairs(views) do
        vim.keymap.set(
            { 'n', 'i', 't' },
            prefix .. spec.key,
            ('<cmd>lua require("mux").open_view(%q)<cr>'):format(name),
            { desc = 'mux: ' .. name }
        )
    end
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'm',
        [[<cmd>lua require('mux').pick_project()<cr>]],
        { desc = 'mux: switch project' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. ']',
        [[<cmd>lua require('mux').cycle_project(1)<cr>]],
        { desc = 'mux: next project' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. '[',
        [[<cmd>lua require('mux').cycle_project(-1)<cr>]],
        { desc = 'mux: previous project' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'q',
        '<cmd>detach<cr>',
        { desc = 'mux: detach to shell' }
    )

    -- free <leader>b for the build view; keep layout-preserving delete on :bd/:bw
    pcall(vim.keymap.del, 'n', '<leader>bd')
    pcall(vim.keymap.del, 'n', '<leader>bw')
    vim.cmd(
        [[cnoreabbrev <expr> bd (getcmdtype()==':' && getcmdline()==#'bd') ? "lua require('mux').bufdelete()" : 'bd']]
    )
    vim.cmd(
        [[cnoreabbrev <expr> bw (getcmdtype()==':' && getcmdline()==#'bw') ? "lua require('mux').bufwipe()" : 'bw']]
    )

    local group = vim.api.nvim_create_augroup('mux', { clear = true })
    vim.api.nvim_create_autocmd(
        'TabClosed',
        { group = group, callback = prune }
    )
    -- ephemeral views close when their process exits. a global TermClose (rather
    -- than a per-job on_exit) also catches terminals re-spawned by session
    -- restore, and keeps the registry's `lifecycle` the single source of truth.
    vim.api.nvim_create_autocmd('TermClose', {
        group = group,
        callback = function(args)
            for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
                local tp = vim.api.nvim_win_get_tabpage(win)
                local name = tab_view[tp]
                if
                    name
                    and views[name]
                    and views[name].lifecycle == 'ephemeral'
                then
                    close_view_tab(tp)
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd('DirChanged', {
        group = group,
        callback = function()
            recipe_cache = {}
        end,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            M.save_session()
        end,
    })

    if not M.load_session() then
        vim.cmd.edit(vim.fn.getcwd())
        tag(vim.api.nvim_get_current_tabpage(), 'edit')
    end

    -- autosave every 5 min (safety net against a hard kill)
    M._timer = vim.uv.new_timer()
    M._timer:start(
        300000,
        300000,
        vim.schedule_wrap(function()
            M.save_session()
        end)
    )
end

return M
