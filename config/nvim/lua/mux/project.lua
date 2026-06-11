local core = require('mux.core')
local session = require('mux.session')

local views = core.views
local VIEW_ORDER = core.VIEW_ORDER
local canon = core.canon

local M = {}

local leave_terminal = core.leave_terminal
local sessions_dir = core.sessions_dir

---@param pid integer?
---@return boolean
local function pid_alive(pid)
    if not pid then
        return false
    end
    local ok, res = pcall(vim.uv.kill, pid, 0)
    return ok and res == 0
end

---@param sock string
---@return boolean
local function socket_live(sock)
    local pidf = (sock:gsub('%.sock$', '.pid'))
    if vim.fn.filereadable(pidf) == 1 then
        return pid_alive(tonumber(vim.fn.readfile(pidf)[1]))
    end
    local ok, ch = pcall(vim.fn.sockconnect, 'pipe', sock, { rpc = true })
    if ok and type(ch) == 'number' and ch > 0 then
        pcall(vim.fn.chanclose, ch)
        return true
    end
    return false
end

---@param slug string
---@return string? root
local function root_for_slug(slug)
    local f = sessions_dir() .. '/' .. slug .. '.root'
    if vim.fn.filereadable(f) == 1 then
        local root = vim.fn.readfile(f)[1]
        if root and root ~= '' then
            return root
        end
    end
    return nil
end

---@return { cwd: string, socket: string, status: string }[]
local function list_entries()
    local entries = {}
    local live = {}
    local socks = vim.fn.glob(core.runtime_dir() .. '/*.sock', true, true)
    table.sort(socks)
    for _, sock in ipairs(socks) do
        if socket_live(sock) then
            local slug = vim.fn.fnamemodify(sock, ':t:r')
            local cwd = root_for_slug(slug)
            if cwd then
                live[slug] = true
                entries[#entries + 1] =
                    { cwd = cwd, socket = sock, status = 'live' }
            end
        end
    end
    local stopped, dead = {}, {}
    for _, rf in ipairs(vim.fn.glob(sessions_dir() .. '/*.root', true, true)) do
        local slug = vim.fn.fnamemodify(rf, ':t:r')
        local root = vim.fn.readfile(rf)[1]
        if root and root ~= '' and not live[slug] then
            if vim.fn.isdirectory(root) == 1 then
                local vimfile = (rf:gsub('%.root$', '.vim'))
                if vim.fn.filereadable(vimfile) == 1 then
                    stopped[#stopped + 1] =
                        { cwd = root, socket = '', status = 'stopped' }
                end
            else
                dead[#dead + 1] = { cwd = root, socket = '', status = 'dead' }
            end
        end
    end
    for _, e in ipairs(stopped) do
        entries[#entries + 1] = e
    end
    for _, e in ipairs(dead) do
        entries[#entries + 1] = e
    end
    return entries
end

M.list_entries = list_entries

---@param items { cwd: string, socket: string, status: string }[]
---@param zoxide_out string? `zoxide query -l` output (one path per line)
---@return { cwd: string, socket: string, status: string }[]
local function merge_sources(items, zoxide_out)
    local entries = {}
    local seen = {}
    for _, item in ipairs(items) do
        local key = canon(item.cwd)
        if
            key ~= ''
            and not seen[key]
            and (
                item.status == 'live'
                or item.status == 'stopped'
                or item.status == 'dead'
            )
        then
            seen[key] = true
            entries[#entries + 1] = item
        end
    end
    for line in (zoxide_out or ''):gmatch('[^\n]+') do
        local key = canon(line)
        if key ~= '' and not seen[key] then
            seen[key] = true
            entries[#entries + 1] = { cwd = line, socket = '', status = 'dir' }
        end
    end
    return entries
end

-- Build and show the project picker from `mux list`, mirroring the CLI's
-- colored output: [live] (green) and [stopped] (amber) rows, each with the
-- ~-shortened path and socket. Selecting connects to that project.
---@param items { cwd: string, socket: string, status: string }[]
local function show_picker(items)
    ---@type { path: string, socket: string?, status: string, disp: string }[]
    local entries = {}
    local w = 0
    for _, item in ipairs(items or {}) do
        local cwd, sock, status = item.cwd, item.socket, item.status
        if
            cwd
            and cwd ~= ''
            and (
                status == 'live'
                or status == 'stopped'
                or status == 'dead'
                or status == 'dir'
            )
        then
            local path = canon(cwd)
            local disp = vim.fn.fnamemodify(path, ':~')
            if #disp > w then
                w = #disp
            end
            entries[#entries + 1] = {
                path = path,
                socket = (sock and sock ~= '' and sock) or nil,
                status = status,
                disp = disp,
            }
        end
    end

    if #entries == 0 then
        return
    end

    -- strip SGR codes so meta lookups work whether fzf hands back the colored
    -- row or a plain one.
    local function strip_ansi(s)
        return (s:gsub('\27%[[%d;]*m', ''))
    end
    local ok, fzf = pcall(require, 'fzf-lua')
    local hl = ok and require('fzf-lua.utils').ansi_from_hl or nil
    -- status tag -> theme highlight group (picker coloring only)
    local tag_hl = {
        live = 'DiagnosticOk',
        stopped = 'DiagnosticWarn',
        dead = 'DiagnosticError',
    }

    local lines, color_lines, meta = {}, {}, {}
    for _, e in ipairs(entries) do
        local tag = e.status == 'dir' and (' '):rep(9)
            or ('%-9s'):format(('[%s]'):format(e.status))
        local rest = (' %-' .. w .. 's  %s'):format(e.disp, e.socket or '')
        rest = (rest:gsub('%s+$', ''))
        lines[#lines + 1] = tag .. rest
        local group = tag_hl[e.status]
        color_lines[#color_lines + 1] = (
            hl
            and group
            and hl(group, tag) .. rest
        ) or (tag .. rest)
        meta[tag .. rest] = {
            path = e.path,
            socket = e.socket,
            status = e.status,
        }
    end

    if ok then
        local actions = {
            ['default'] = function(sel)
                local entry = sel and sel[1] and meta[strip_ansi(sel[1])]
                if entry and entry.status ~= 'dead' then
                    M._connect(entry)
                end
            end,
        }
        local parts = {}
        for _, name in ipairs(VIEW_ORDER) do
            local spec = views[name]
            actions['ctrl-' .. spec.key] = function(sel)
                local entry = sel and sel[1] and meta[strip_ansi(sel[1])]
                if entry and entry.status ~= 'dead' then
                    M._connect(entry, name)
                end
            end
            parts[#parts + 1] = ('%s %s'):format(
                hl('FzfLuaHeaderBind', '^' .. spec.key:upper()),
                hl('FzfLuaHeaderText', name)
            )
        end
        local function lifecycle(verb, sel)
            local entry = sel and sel[1] and meta[strip_ansi(sel[1])]
            if entry and entry.status == 'dir' then
                return
            end
            if entry and entry.status == 'dead' and verb == 'stop' then
                return
            end
            if entry and entry.path then
                if canon(entry.path) == canon(vim.fn.getcwd()) then
                    if verb == 'kill' then
                        session.kill_session()
                    else
                        session.stop_session()
                    end
                    return
                end
                vim.system({ 'mux', verb, entry.path }, function()
                    vim.schedule(M.pick_project)
                end)
                return
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

---@param entry { path: string, socket: string? }
---@param view string?
function M._connect(entry, view)
    if not entry then
        return
    end
    leave_terminal()
    local function go(sock)
        if not sock or sock == '' then
            return
        end
        local function finish()
            session.record_last(entry.path)
            vim.cmd('connect ' .. vim.fn.fnameescape(sock))
        end
        if view then
            local expr = (
                "luaeval('(function() "
                .. "require([[mux]]).open_view([[%s]]) return 1 end)()')"
            ):format(view)
            vim.system(
                { 'nvim', '--server', sock, '--remote-expr', expr },
                function()
                    vim.schedule(finish)
                end
            )
        else
            finish()
        end
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
            end
        end)
    end)
end

function M.pick_project()
    leave_terminal()
    local items = list_entries()
    local function show(zoxide_out)
        vim.schedule(function()
            show_picker(merge_sources(items, zoxide_out))
        end)
    end
    local ok = pcall(
        vim.system,
        { 'zoxide', 'query', '-l' },
        { text = true },
        function(z)
            show((z.code == 0 and z.stdout) or '')
        end
    )
    if not ok then
        show('')
    end
end

---@param step integer 1 = next live project, -1 = previous (wraps)
function M.cycle_project(step)
    leave_terminal()
    local entries = {}
    for _, item in ipairs(list_entries()) do
        if item.status == 'live' and item.socket ~= '' then
            entries[#entries + 1] = { cwd = item.cwd, sock = item.socket }
        end
    end
    vim.schedule(function()
        if #entries < 2 then
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
            session.record_last(target.cwd)
            vim.cmd('connect ' .. vim.fn.fnameescape(target.sock))
        end
    end)
end

---@param cb fun(root?: string, sock?: string)
local function with_latest_live_other(cb)
    local live = {}
    for _, item in ipairs(list_entries()) do
        if item.cwd and item.status == 'live' and item.socket ~= '' then
            live[canon(item.cwd)] = item.socket
        end
    end
    vim.schedule(function()
        local cur = canon(vim.fn.getcwd())
        local hf = core.state_dir() .. '/history'
        local hist = vim.fn.filereadable(hf) == 1 and vim.fn.readfile(hf) or {}
        for i = #hist, 1, -1 do
            local root = canon(hist[i])
            local sock = root ~= '' and root ~= cur and live[root]
            if sock then
                cb(root, sock)
                return
            end
        end
        cb(nil, nil)
    end)
end

function M.last_session()
    leave_terminal()
    with_latest_live_other(function(root, sock)
        if sock then
            M._connect({ path = root, socket = sock })
        end
    end)
end

-- Killing the last tabpage: hop the client to the latest live project, then
-- soft-stop this session so it stays resumable. With no other live project the
-- stop drops the client to the shell -- like tmux detach-on-destroy=off.
function M.exit_to_latest()
    with_latest_live_other(function(root, sock)
        if sock then
            session.record_last(root)
            pcall(vim.cmd, 'connect ' .. vim.fn.fnameescape(sock))
        end
        session.stop_session()
    end)
end

return M
