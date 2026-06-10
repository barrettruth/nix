local core = require('mux.core')
local session = require('mux.session')

local views = core.views
local VIEW_ORDER = core.VIEW_ORDER
local canon = core.canon

local M = {}

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
                        session.kill_session()
                    else
                        session.stop_session()
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
        session.record_last(entry.path)
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
                session.record_last(target.cwd)
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
            local hf = core.state_dir() .. '/history'
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

return M
