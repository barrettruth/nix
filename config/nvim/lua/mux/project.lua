local core = require('mux.core')
local session = require('mux.session')

local views = core.views
local VIEW_ORDER = core.VIEW_ORDER
local canon = core.canon

local M = {}

---@param out string? `mux list` stdout: "cwd<TAB>socket<TAB>status" per line
---@return { cwd: string, socket: string, status: string }[]
local function parse_list(out)
    local entries = {}
    for line in (out or ''):gmatch('[^\n]+') do
        local cwd, socket, status = line:match('^(.-)\t(.-)\t(.+)$')
        if cwd then
            entries[#entries + 1] =
                { cwd = cwd, socket = socket, status = status }
        end
    end
    return entries
end

-- Build and show the project picker from `mux list`, mirroring the CLI's
-- colored output: [live] (green) and [stopped] (amber) rows, each with the
-- ~-shortened path and socket. Selecting connects to that project.
---@param list_out string `mux list` stdout: "cwd<TAB>socket<TAB>status" per line
local function show_picker(list_out)
    ---@type { path: string, socket: string?, status: string, disp: string }[]
    local entries = {}
    local w = 0
    for _, item in ipairs(parse_list(list_out)) do
        local cwd, sock, status = item.cwd, item.socket, item.status
        if cwd and cwd ~= '' and (status == 'live' or status == 'stopped') then
            local path = canon(cwd)
            local disp = vim.fn.fnamemodify(path, ':~')
            if #disp > w then
                w = #disp
            end
            entries[#entries + 1] = {
                path = path,
                socket = (sock ~= '' and sock) or nil,
                status = status,
                disp = disp,
            }
        end
    end

    if #entries == 0 then
        vim.notify('mux: no projects found', vim.log.levels.WARN)
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
    local tag_hl = { live = 'DiagnosticOk', stopped = 'DiagnosticWarn' }

    local lines, color_lines, meta = {}, {}, {}
    for _, e in ipairs(entries) do
        local tag = ('%-9s'):format(('[%s]'):format(e.status))
        local rest = (' %-' .. w .. 's  %s'):format(e.disp, e.socket or '')
        rest = (rest:gsub('%s+$', ''))
        lines[#lines + 1] = tag .. rest
        color_lines[#color_lines + 1] = (
            hl and hl(tag_hl[e.status], tag) .. rest
        ) or (tag .. rest)
        meta[tag .. rest] = { path = e.path, socket = e.socket }
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
            parts[#parts + 1] = ('%s %s'):format(
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
    vim.system({ 'mux', 'list' }, { text = true }, function(res)
        vim.schedule(function()
            show_picker(res.stdout or '')
        end)
    end)
end

---@param step integer 1 = next live project, -1 = previous (wraps)
function M.cycle_project(step)
    vim.system({ 'mux', 'list' }, { text = true }, function(res)
        local entries = {}
        for _, item in ipairs(parse_list(res.stdout)) do
            local cwd, sock, status = item.cwd, item.socket, item.status
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

---@param cb fun(root?: string, sock?: string)
local function with_latest_live_other(cb)
    vim.system({ 'mux', 'list' }, { text = true }, function(res)
        local live = {}
        for _, item in ipairs(parse_list(res.stdout)) do
            local cwd, sock, status = item.cwd, item.socket, item.status
            if cwd and status == 'live' and sock ~= '' then
                live[canon(cwd)] = sock
            end
        end
        vim.schedule(function()
            local cur = canon(vim.fn.getcwd())
            local hf = core.state_dir() .. '/history'
            local hist = vim.fn.filereadable(hf) == 1 and vim.fn.readfile(hf)
                or {}
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
    end)
end

function M.last_session()
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
