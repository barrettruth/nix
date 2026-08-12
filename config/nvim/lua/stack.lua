---@class stack.Pr
---@field number integer
---@field title string
---@field headRefName string
---@field baseRefName string

local M = {}

local function notify(msg, level)
    vim.notify('[stack]: ' .. msg, level or vim.log.levels.INFO)
end

---The pull request the current buffer is showing, if it is a guh buffer.
---@return integer?
local function current_pr()
    local name = vim.api.nvim_buf_get_name(0)
    return tonumber(name:match('^guh://[^/]+/[^/]+/%a+/(%d+)$'))
end

---The branch the working copy is on.
---
---git answers first because every repository has it, and in a colocated one it
---reports nothing until a branch really is checked out, at which point jj has
---moved the working copy to a fresh child of it and would answer nothing.
---Failing that, jj is asked for the nearest bookmark at or under the working
---copy, since starting the next layer leaves it on an unbookmarked change.
---@return string?
local function current_branch()
    local git = vim.system({ 'git', 'branch', '--show-current' }, {
        text = true,
    }):wait()
    if git.code == 0 and vim.trim(git.stdout) ~= '' then
        return vim.trim(git.stdout)
    end

    local jj = vim.system({
        'jj',
        'log',
        '--no-graph',
        '-r',
        'heads(::@ & bookmarks())',
        '-T',
        'bookmarks',
    }, { text = true }):wait()
    if jj.code ~= 0 then
        return nil
    end
    return vim.trim(jj.stdout):match('^[^%s*]+')
end

---Every open pull request in the current repository.
---@param on_done fun(prs: stack.Pr[])
local function fetch(on_done)
    vim.system({
        'gh',
        'pr',
        'list',
        '--state',
        'open',
        '--limit',
        '100',
        '--json',
        'number,title,headRefName,baseRefName',
    }, { text = true }, function(out)
        vim.schedule(function()
            if out.code ~= 0 then
                local err = vim.trim(out.stderr or '')
                notify(
                    err ~= '' and err or 'gh pr list failed',
                    vim.log.levels.ERROR
                )
                return
            end
            local ok, prs = pcall(vim.json.decode, out.stdout)
            if not ok or type(prs) ~= 'table' then
                notify('could not read gh output', vim.log.levels.ERROR)
                return
            end
            on_done(prs)
        end)
    end)
end

---The stack holding `number`, ordered bottom first.
---
---Walking down follows each pull request's single base, so it is never
---ambiguous. Walking up can meet two pull requests sharing a base, which is a
---fork: the layer above is genuinely unknown, so refuse rather than pick one.
---@param prs stack.Pr[]
---@param number integer
---@return stack.Pr[]? ordered
---@return string? err
local function chain(prs, number)
    local by_head, children, start = {}, {}, nil
    for _, pr in ipairs(prs) do
        by_head[pr.headRefName] = pr
        children[pr.baseRefName] = children[pr.baseRefName] or {}
        table.insert(children[pr.baseRefName], pr)
        if pr.number == number then
            start = pr
        end
    end
    if not start then
        return nil, ('#%d is not an open pull request here'):format(number)
    end

    local ordered, below = { start }, start
    while by_head[below.baseRefName] do
        below = by_head[below.baseRefName]
        table.insert(ordered, 1, below)
    end

    local above = start
    while true do
        local next_up = children[above.headRefName]
        if not next_up then
            break
        end
        if #next_up > 1 then
            local ns = vim.tbl_map(function(pr)
                return '#' .. pr.number
            end, next_up)
            return nil,
                ('stack forks above #%d into %s'):format(
                    above.number,
                    table.concat(ns, ', ')
                )
        end
        above = next_up[1]
        table.insert(ordered, above)
    end

    return ordered
end

---@param ordered stack.Pr[]
---@param number integer
local function position(ordered, number)
    for i, pr in ipairs(ordered) do
        if pr.number == number then
            return i
        end
    end
end

---Open the layer at `index` and say where in the stack it landed.
---@param ordered stack.Pr[]
---@param index integer
local function open(ordered, index)
    local pr = ordered[index]
    vim.cmd.Guh(tostring(pr.number))
    notify(('%d/%d %s'):format(index, #ordered, pr.title))
end

---List the stack holding the current buffer's pull request, or the pull
---request for the current branch, and open whichever is chosen. A stack of
---one has nothing to choose, so it opens straight away.
function M.list()
    local number = current_pr()
    fetch(function(prs)
        if not number then
            local branch = current_branch()
            for _, pr in ipairs(prs) do
                if pr.headRefName == branch then
                    number = pr.number
                end
            end
        end
        if not number then
            notify('no pull request here', vim.log.levels.WARN)
            return
        end

        local ordered, err = chain(prs, number)
        if not ordered then
            notify(err, vim.log.levels.ERROR)
            return
        end

        if #ordered == 1 then
            open(ordered, 1)
            return
        end

        vim.ui.select(ordered, {
            prompt = 'Select a pull request:',
            kind = 'stack.pr',
            format_item = function(pr)
                return ('%s #%d  %s'):format(
                    pr.number == number and '*' or ' ',
                    pr.number,
                    pr.title
                )
            end,
        }, function(choice)
            if choice then
                open(ordered, position(ordered, choice.number))
            end
        end)
    end)
end

---Move `delta` layers through the stack, wrapping at either end.
---@param delta integer
function M.walk(delta)
    local number = current_pr()
    if not number then
        notify('not in a pull request buffer', vim.log.levels.WARN)
        return
    end

    fetch(function(prs)
        local ordered, err = chain(prs, number)
        if not ordered then
            notify(err, vim.log.levels.ERROR)
            return
        end

        local at = position(ordered, number)
        open(ordered, (at - 1 + delta) % #ordered + 1)
    end)
end

return M
