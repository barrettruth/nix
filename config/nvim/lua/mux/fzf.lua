local candidates = require('mux.candidates')
local command = require('mux.command')
local server = require('mux.server')

local M = {}

---@return boolean
local function load_fzf()
    local ok, err = pcall(function()
        require('config.lz').load('ibhagwan/fzf-lua')
        require('fzf-lua')
    end)

    if not ok then
        vim.notify(
            'mux: cannot load fzf-lua: ' .. tostring(err),
            vim.log.levels.ERROR
        )
    end

    return ok
end

---@param ok? true
---@param err? string
local function done(ok, err)
    if not ok then
        vim.notify('mux: ' .. tostring(err), vim.log.levels.ERROR)
    end
end

---@param candidate mux.Candidate
---@param view_name? string
---@return nil
local function select(candidate, view_name)
    if candidate.server then
        server.switch(candidate.server, done, nil, view_name)
    else
        server.connect(candidate.root, done, nil, view_name)
    end
end

---@param candidate mux.Candidate
---@return mux.Server?
local function active(candidate)
    if candidate.server then
        return candidate.server
    end

    vim.notify(
        'mux: ' .. candidate.root .. ' is not active',
        vim.log.levels.ERROR
    )
end

---@param selected string[]
---@return mux.Candidate?
local function picked(selected)
    local data = selected[1] and selected[1]:match('^([^\t]+)\t')
    local ok, candidate = pcall(vim.json.decode, data or '')
    return ok
            and type(candidate) == 'table'
            and type(candidate.root) == 'string'
            and candidate
        or nil
end

---@param query string
---@return nil
local function create(query)
    local complete = false
    local target, err
    command.ensure(query, function(ensured, ensure_err)
        target = ensured
        err = ensure_err
        complete = true
    end)

    if
        not complete
        and not vim.wait(25000, function()
            return complete
        end, 50)
    then
        done(nil, 'timed out creating ' .. query)
        return
    end

    if not target then
        done(nil, err)
    end
end

---@param value string
---@param group string
---@return string
local function highlight(value, group)
    return require('fzf-lua.utils').ansi_from_hl(group, value)
end

---@param items mux.Candidate[]
---@return string[]
local function entries(items)
    local current = server.state().server
    local labels = {}
    local width = 0

    for i, candidate in ipairs(items) do
        local label = candidate.server and server.label(candidate.server)
            or vim.fn.fnamemodify(candidate.root, ':t')
        labels[i] = label
        width = math.max(width, vim.fn.strdisplaywidth(label))
    end

    local rendered = {}
    for i, candidate in ipairs(items) do
        local current_root = current and current.root == candidate.root
        local marker = current_root and highlight('*', 'Special')
            or candidate.server and highlight('+', 'DiagnosticOk')
            or ' '
        local padding =
            string.rep(' ', width - vim.fn.strdisplaywidth(labels[i]))
        rendered[i] = ('%s\t%s %s%s  %s'):format(
            vim.json.encode(candidate),
            marker,
            labels[i],
            padding,
            highlight(vim.fn.fnamemodify(candidate.root, ':~'), 'Directory')
        )
    end

    return rendered
end

---@param query? string
---@return nil
local function open(query)
    local function contents(cb)
        candidates.list(function(items, err)
            if err then
                local level = #items == 0 and vim.log.levels.ERROR
                    or vim.log.levels.WARN
                vim.notify('mux: zoxide: ' .. err, level)
            end

            for _, entry in ipairs(entries(items)) do
                cb(entry)
            end
            cb(nil)
        end)
    end

    local function select_action(name)
        return {
            fn = function(selected)
                local candidate = picked(selected)
                if candidate then
                    select(candidate, name)
                end
            end,
        }
    end

    require('fzf-lua').fzf_exec(contents, {
        prompt = 'mux> ',
        previewer = false,
        header = ('%s vcs | %s create | %s edit | %s zsh | %s reload | %s remove | %s attach'):format(
            highlight('<c-v>', 'FzfLuaHeaderBind'),
            highlight('<c-a>', 'FzfLuaHeaderBind'),
            highlight('<c-e>', 'FzfLuaHeaderBind'),
            highlight('<c-z>', 'FzfLuaHeaderBind'),
            highlight('<c-r>', 'FzfLuaHeaderBind'),
            highlight('<c-x>', 'FzfLuaHeaderBind'),
            highlight('<enter>', 'FzfLuaHeaderBind')
        ),
        fzf_opts = {
            ['--query'] = query,
            ['--delimiter'] = '[\t]',
            ['--with-nth'] = '2..',
            ['--no-multi'] = true,
            ['--tiebreak'] = 'index',
        },
        actions = {
            ['ctrl-v'] = select_action('vcs'),
            ['ctrl-e'] = select_action('edit'),
            ['ctrl-z'] = select_action('zsh'),
            ['ctrl-a'] = {
                fn = function(selected, opts)
                    local query = vim.trim(opts.last_query or '')
                    if query ~= '' then
                        create(query)
                        return
                    end

                    local candidate = picked(selected)
                    if not candidate then
                        done(nil, 'no path selected')
                    elseif candidate.server then
                        done(
                            nil,
                            'server already exists for ' .. candidate.root
                        )
                    else
                        create(candidate.root)
                    end
                end,
                postfix = 'clear-query+first',
                reload = true,
            },
            enter = select_action(),
            ['ctrl-r'] = {
                fn = function(selected)
                    local candidate = picked(selected)
                    local target = candidate and active(candidate)
                    if target then
                        server.reload_target(target, done)
                    end
                end,
            },
            ['ctrl-x'] = {
                fn = function(selected, opts)
                    local candidate = picked(selected)
                    require('fzf-lua').win.close()
                    if not candidate then
                        return
                    end
                    local current = server.state().server
                    local removing_current = current
                        and current.root == candidate.root
                    candidates.remove(candidate, function(ok, err)
                        done(ok, err)
                        if not removing_current or not ok then
                            vim.schedule(function()
                                if
                                    vim.v.exiting == vim.NIL
                                    and #vim.api.nvim_list_uis() > 0
                                then
                                    open(opts.last_query)
                                end
                            end)
                        end
                    end)
                end,
                reuse = true,
            },
        },
    })
end

---@return nil
function M.pick()
    if not load_fzf() then
        return
    end

    open()
end

return M
