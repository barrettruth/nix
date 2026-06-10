-- mux: in-Neovim "multiplexer" brain. Each "view" is a tagged tabpage; switching
-- projects is `:connect` to another per-project nvim server (see scripts/mux).

local M = {}

---@class mux.ViewSpec
---@field key string single char appended to the `<a-x>` prefix to open this view
---@field kind 'editor'|'vcs'|'terminal'|'task' how the tab's content is built
---@field cmd? string[] terminal command (terminal kind), defaults to `just <recipe>` for tasks
---@field restore_cmd? string[] command used instead of `cmd` when restoring a saved session
---@field recipe? string justfile recipe name (task kind)
---@field lifecycle? 'ephemeral'|'persistent' ephemeral tabs auto-close when their terminal exits
---@field restore? boolean re-materialize this view when a saved session is loaded

---@type table<string, mux.ViewSpec>
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

local VIEW_ORDER = { 'edit', 'vcs', 'ai', 'run', 'build', 'test', 'zsh' }

local AUTOSAVE_INTERVAL_MS = 5 * 60 * 1000

-- tabpage handle -> view name
---@type table<integer, string>
local tab_view = {}

---@param tabpage integer
---@param name string
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

---@param name string
---@return integer? tabpage handle of the open view, or nil if none
local function find_view(name)
    for tp, v in pairs(tab_view) do
        if v == name and vim.api.nvim_tabpage_is_valid(tp) then
            return tp
        end
    end
    return nil
end

-- cwd -> set of justfile recipe names (cleared on DirChanged).
local recipe_cache = {}

-- Whether `cwd`'s justfile defines `recipe`, caching `just --summary` per cwd.
---@param cwd string
---@param recipe string
---@return boolean
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

---@param tp integer
local function close_view_tab(tp)
    vim.schedule(function()
        if not vim.api.nvim_tabpage_is_valid(tp) then
            return
        end
        if #vim.api.nvim_list_tabpages() <= 1 then
            -- Hop to the most-recently-used live project
            -- TODO: check this Reset this lone tab to a clean edit view first so the server
            -- we leave behind isn't holding a dead terminal;
            -- last_session() :detaches only when nothing else is live.
            local win = vim.api.nvim_tabpage_get_win(tp)
            vim.api.nvim_win_call(win, function()
                pcall(vim.cmd, 'enew')
            end)
            tab_view[tp] = 'edit'
            M.last_session()
            return
        end
        local win = vim.api.nvim_tabpage_get_win(tp)
        vim.api.nvim_win_call(win, function()
            pcall(vim.cmd, 'tabclose')
        end)
        tab_view[tp] = nil
    end)
end

---@param name string
---@param restoring boolean true when re-opening from a saved session
local function materialize(name, restoring)
    local spec = views[name]
    local cwd = vim.fn.getcwd()
    if spec.kind == 'editor' then
        vim.cmd.edit(cwd)
    elseif spec.kind == 'vcs' then
        pcall(vim.cmd, 'Git|only')
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

---@param spec string|{ view?: string, win?: integer, tab?: integer, create?: boolean }
---@return integer? win
---@return integer|string tp
function M.resolve_view(spec)
    if type(spec) == 'string' then
        spec = { view = spec }
    end
    spec = spec or {}

    if spec.win ~= nil then
        local win = tonumber(spec.win)
        if not (win and vim.api.nvim_win_is_valid(win)) then
            return nil, 'invalid window: ' .. tostring(spec.win)
        end
        return win, vim.api.nvim_win_get_tabpage(win)
    end

    if spec.tab ~= nil then
        local tp = vim.api.nvim_list_tabpages()[tonumber(spec.tab) or -1]
        if not (tp and vim.api.nvim_tabpage_is_valid(tp)) then
            return nil, 'invalid tab: ' .. tostring(spec.tab)
        end
        return vim.api.nvim_tabpage_get_win(tp), tp
    end

    local name = spec.view
    if not name then
        return nil, 'resolve_view: need view, win, or tab'
    end
    if not views[name] then
        return nil, 'unknown view: ' .. tostring(name)
    end
    local tp = find_view(name)
    if not tp then
        if spec.create == false then
            return nil, 'view not open: ' .. name
        end
        local cur = vim.api.nvim_get_current_tabpage()
        local saved_alt = M._alt
        vim.cmd.tabnew()
        tp = vim.api.nvim_get_current_tabpage()
        tag(tp, name)
        materialize(name, false)
        if vim.api.nvim_tabpage_is_valid(cur) then
            vim.api.nvim_set_current_tabpage(cur)
        end
        M._alt = saved_alt
    end
    return vim.api.nvim_tabpage_get_win(tp), tp
end

---@param spec string|table
---@param fn fun(): any
---@return any result, string? err
function M.in_view(spec, fn)
    local win, tp = M.resolve_view(spec)
    if not win then
        return nil, tp
    end
    return vim.api.nvim_win_call(win, fn), nil
end

function M.state()
    local cur = vim.api.nvim_get_current_tabpage()
    local tabs = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local win = vim.api.nvim_tabpage_get_win(tp)
        local buf = vim.api.nvim_win_get_buf(win)
        tabs[#tabs + 1] = {
            tab = vim.api.nvim_tabpage_get_number(tp),
            view = tab_view[tp],
            win = win,
            current = tp == cur,
            buftype = vim.bo[buf].buftype,
            filetype = vim.bo[buf].filetype,
        }
    end
    return { current_view = tab_view[cur], tabs = tabs }
end

local bufremove = require('config.bufremove')

function M.bufdelete()
    bufremove(false)
end

function M.bufwipe()
    bufremove(true)
end

---@param p string?
---@return string
local function canon(p)
    if not p or p == '' then
        return ''
    end
    return (vim.fn.fnamemodify(p, ':p'):gsub('/$', ''))
end

-- Build and show the project picker from `mux list`
-- Include live sessions, stopped sessions, and zoxide candidates.
---@param list_out string `mux list` stdout: "cwd<TAB>socket<TAB>status" per line
---@param zoxide_out string `zoxide query -l` stdout: one path per line
local function show_picker(list_out, zoxide_out)
    local live, stopped = {}, {} -- canon cwd -> socket; canon cwd -> true
    for line in (list_out or ''):gmatch('[^\n]+') do
        local cwd, sock, status = line:match('^(.-)\t(.-)\t(.+)$')
        if cwd then
            cwd = canon(cwd)
            if status == 'live' and sock ~= '' then
                live[cwd] = sock
            elseif status == 'stopped' then
                stopped[cwd] = true
            end
        end
    end

    -- strip SGR codes so meta lookups work whether fzf hands back the colored
    -- row or a plain one.
    local function strip_ansi(s)
        return (s:gsub('\27%[[%d;]*m', ''))
    end
    local ok, fzf = pcall(require, 'fzf-lua')
    local hl = ok and require('fzf-lua.utils').ansi_from_hl or nil
    -- status tag -> theme highlight group (picker coloring only)
    local tag_hl =
        { live = 'DiagnosticOk', stopped = 'DiagnosticWarn', new = 'Comment' }

    local here = canon(vim.fn.getcwd())
    local seen, lines, color_lines, meta = {}, {}, {}, {}
    local function add(path)
        if not path or path == '' then
            return
        end
        path = canon(path)
        if seen[path] then
            return
        end
        local status = (live[path] and 'live')
            or (stopped[path] and 'stopped')
            or 'new'
        -- only list candidates that are git repos
        if status == 'new' and vim.uv.fs_stat(path .. '/.git') == nil then
            return
        end
        seen[path] = true
        local tagstr = ('%-9s'):format(('[%s]'):format(status))
        local mark = (path == here) and '*' or ' '
        local rest = (' %s %s'):format(mark, vim.fn.fnamemodify(path, ':~'))
        lines[#lines + 1] = tagstr .. rest
        color_lines[#color_lines + 1] = (
            hl and hl(tag_hl[status], tagstr) .. rest
        ) or (tagstr .. rest)
        meta[tagstr .. rest] = { path = path, socket = live[path] }
    end
    for cwd in pairs(live) do
        add(cwd)
    end
    for cwd in pairs(stopped) do
        add(cwd)
    end
    for line in (zoxide_out or ''):gmatch('[^\n]+') do
        add(line)
    end

    if #lines == 0 then
        vim.notify('mux: no projects found', vim.log.levels.WARN)
        return
    end

    if ok then
        local actions = {
            ['default'] = function(sel)
                if sel and sel[1] then
                    M._connect(meta[strip_ansi(sel[1])])
                end
            end,
        }
        local parts = {}
        for _, name in ipairs(VIEW_ORDER) do
            local spec = views[name]
            actions['ctrl-' .. spec.key] = function(sel)
                if sel and sel[1] then
                    M._connect(meta[strip_ansi(sel[1])], name)
                end
            end
            parts[#parts + 1] = ('%s to %s'):format(
                hl('FzfLuaHeaderBind', '^' .. spec.key:upper()),
                hl('FzfLuaHeaderText', name)
            )
        end
        local function lifecycle(verb, sel)
            local entry = sel and sel[1] and meta[strip_ansi(sel[1])]
            if entry and entry.path then
                if canon(entry.path) == canon(vim.fn.getcwd()) then
                    if verb == 'kill' then
                        M.kill_session()
                    else
                        M.stop_session()
                    end
                    return
                end
                vim.system({ 'mux', verb, entry.path }):wait()
            end
            vim.schedule(M.pick_project)
        end
        actions['ctrl-s'] = function(sel)
            lifecycle('stop', sel)
        end
        parts[#parts + 1] = ('%s %s'):format(
            hl('FzfLuaHeaderBind', '^S'),
            hl('FzfLuaHeaderText', 'stop')
        )
        actions['ctrl-x'] = function(sel)
            lifecycle('kill', sel)
        end
        parts[#parts + 1] = ('%s %s'):format(
            hl('FzfLuaHeaderBind', '^X'),
            hl('FzfLuaHeaderText', 'kill')
        )
        fzf.fzf_exec(color_lines, {
            prompt = 'project> ',
            fzf_args = ((vim.env.FZF_DEFAULT_OPTS or '')
                :gsub('%-%-bind=ctrl%-a:select%-all', '')
                :gsub('--color=[^%s]+', '')),
            keymap = { fzf = { ['ctrl-z'] = false } },
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

---@param root string project root path
local function push_history(root)
    root = canon(root)
    if root == '' then
        return
    end
    local dir = vim.fn.stdpath('state') .. '/mux'
    pcall(vim.fn.mkdir, dir, 'p')
    local hf = dir .. '/history'
    local kept = {}
    if vim.fn.filereadable(hf) == 1 then
        for _, line in ipairs(vim.fn.readfile(hf)) do
            if line ~= '' and canon(line) ~= root then
                kept[#kept + 1] = line
            end
        end
    end
    kept[#kept + 1] = root
    while #kept > 50 do
        table.remove(kept, 1)
    end
    pcall(vim.fn.writefile, kept, hf)
end

---@param root string project root path
local function record_last(root)
    if not root or root == '' then
        return
    end
    root = canon(root)
    local dir = vim.fn.stdpath('state') .. '/mux'
    pcall(vim.fn.mkdir, dir, 'p')
    push_history(root)
    pcall(vim.fn.writefile, { root }, dir .. '/last')
end

---@param root string project root path
local function forget_history(root)
    root = canon(root)
    if root == '' then
        return
    end
    local hf = vim.fn.stdpath('state') .. '/mux/history'
    if vim.fn.filereadable(hf) ~= 1 then
        return
    end
    local kept = {}
    for _, line in ipairs(vim.fn.readfile(hf)) do
        if line ~= '' and canon(line) ~= root then
            kept[#kept + 1] = line
        end
    end
    pcall(vim.fn.writefile, kept, hf)
end

---@param root string project root path
local function clear_last(root)
    root = canon(root)
    local lf = vim.fn.stdpath('state') .. '/mux/last'
    if vim.fn.filereadable(lf) ~= 1 then
        return
    end
    local cur = vim.fn.readfile(lf)[1]
    if cur and canon(cur) == root then
        pcall(vim.fn.delete, lf)
    end
end

---@param entry { path: string, socket: string? }
---@param view string?
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
            local cwd, sock, status = line:match('^(.-)\t(.-)\t(.+)$')
            if status == 'live' and sock ~= '' then
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

function M.last_session()
    vim.system({ 'mux', 'list' }, { text = true }, function(res)
        local live = {}
        for line in (res.stdout or ''):gmatch('[^\n]+') do
            local cwd, sock, status = line:match('^(.-)\t(.-)\t(.+)$')
            if cwd and status == 'live' and sock ~= '' then
                live[canon(cwd)] = sock
            end
        end
        vim.schedule(function()
            local cur = canon(vim.fn.getcwd())
            local hf = vim.fn.stdpath('state') .. '/mux/history'
            local hist = {}
            if vim.fn.filereadable(hf) == 1 then
                hist = vim.fn.readfile(hf)
            end
            for i = #hist, 1, -1 do
                local root = canon(hist[i])
                local sock = root ~= '' and root ~= cur and live[root]
                if sock then
                    M._connect({ path = root, socket = sock })
                    return
                end
            end
            pcall(vim.cmd, 'detach')
        end)
    end)
end

---@return string dir
local function sessions_dir()
    return vim.fn.stdpath('state') .. '/mux/sessions'
end

---@return string
local function session_file()
    local env = vim.env.MUX_SESSION_FILE
    if env and env ~= '' then
        return env
    end
    local slug = vim.fn.getcwd():gsub('[^%w._-]', '_')
    return sessions_dir() .. '/' .. slug .. '.vim'
end

-- Soft stop: write all buffers and quit, leaving the saved session
-- so a next attach may resume the layout.
function M.stop_session()
    pcall(vim.cmd, 'silent! wall')
    vim.schedule(function()
        pcall(vim.cmd, 'qall!')
    end)
end

-- Hard kill: delete the saved session and history/last entries, then quit.
function M.kill_session()
    M._killing = true
    local f = session_file()
    pcall(vim.fn.delete, f)
    pcall(vim.fn.delete, (f:gsub('%.vim$', '.root')))
    local root = vim.fn.getcwd()
    forget_history(root)
    clear_last(root)
    vim.schedule(function()
        pcall(vim.cmd, 'qall!')
    end)
end

-- Reload in place: save the layout, then `:restart +qall!` re-execs the server
-- with new config and reattaches the UI (setup restores the tabs).
function M.reload()
    if #vim.api.nvim_list_uis() == 0 then
        return -- no UI to reattach; :restart would dangle the new server
    end
    M.save_session()
    pcall(vim.cmd, 'silent! wall')
    pcall(vim.cmd, 'restart +qall!')
end

function M.save_session()
    if M._killing then
        return
    end
    local map = {}
    for tp, view in pairs(tab_view) do
        if vim.api.nvim_tabpage_is_valid(tp) then
            map[tostring(vim.api.nvim_tabpage_get_number(tp))] = view
        end
    end
    vim.g.MuxViews = vim.json.encode(map)
    local f = session_file()
    vim.fn.mkdir(vim.fn.fnamemodify(f, ':h'), 'p')
    pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(f))
    pcall(vim.fn.writefile, { vim.fn.getcwd() }, (f:gsub('%.vim$', '.root')))
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
        prefix .. '<bs>',
        [[<cmd>lua require('mux').last_session()<cr>]],
        { desc = 'mux: last project' }
    )
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
        prefix .. 'd',
        '<cmd>detach<cr>',
        { desc = 'mux: detach to shell' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 's',
        [[<cmd>lua require('mux').stop_session()<cr>]],
        { desc = 'mux: stop session (resumable)' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'x',
        [[<cmd>lua require('mux').kill_session()<cr>]],
        { desc = 'mux: kill session (hard)' }
    )
    vim.keymap.set(
        { 'n', 'i', 't' },
        prefix .. 'R',
        [[<cmd>lua require('mux').reload()<cr>]],
        { desc = 'mux: reload session (restart)' }
    )

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
    vim.api.nvim_create_autocmd('TabLeave', {
        group = group,
        callback = function()
            M._alt = vim.api.nvim_get_current_tabpage()
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

    M._timer = vim.uv.new_timer()
    M._timer:start(
        AUTOSAVE_INTERVAL_MS,
        AUTOSAVE_INTERVAL_MS,
        vim.schedule_wrap(function()
            M.save_session()
        end)
    )
end

return M
