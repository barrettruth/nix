local M = {}

---@alias config.forge.RouteName
---| 'prs.open'
---| 'issues.open'
---| 'ci.current_branch'
---| 'browse.contextual'
---| 'releases.all'

---@alias config.forge.LocalPickerName
---| 'commits'
---| 'buffer_commits'
---| 'branches'
---| 'worktrees'
---| 'stash'
---| 'tags'

---@class config.forge.RouteEntry
---@field kind 'route'
---@field label string
---@field route config.forge.RouteName

---@class config.forge.PickerEntryValue
---@field kind 'picker'
---@field label string
---@field picker config.forge.LocalPickerName

---@alias config.forge.MenuEntryValue config.forge.RouteEntry|config.forge.PickerEntryValue

---@type config.forge.MenuEntryValue[]
local menu_entries = {
    { kind = 'route', label = 'PRs', route = 'prs.open' },
    { kind = 'route', label = 'Issues', route = 'issues.open' },
    { kind = 'route', label = 'CI', route = 'ci.current_branch' },
    { kind = 'route', label = 'Browse', route = 'browse.contextual' },
    { kind = 'route', label = 'Releases', route = 'releases.all' },
    { kind = 'picker', label = 'Commits', picker = 'commits' },
    { kind = 'picker', label = 'Buffer Commits', picker = 'buffer_commits' },
    { kind = 'picker', label = 'Branches', picker = 'branches' },
    { kind = 'picker', label = 'Worktrees', picker = 'worktrees' },
    { kind = 'picker', label = 'Stash', picker = 'stash' },
    { kind = 'picker', label = 'Tags', picker = 'tags' },
}

---@param plugin string
local function load(plugin)
    require('config.lz').load(plugin)
end

---@return table
function M.load()
    load('barrettruth/forge.nvim')
    return require('forge')
end

---@return table
local function fzf()
    load('ibhagwan/fzf-lua')
    return require('fzf-lua')
end

---@param message string
local function warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

---@param selected string[]?
---@return string?
local function branch_name(selected)
    local line = selected and selected[1]
    if type(line) ~= 'string' or line == '' then
        return nil
    end
    if line:match('%(HEAD detached') or line:match('%(no branch') then
        return nil
    end
    local _, branch = line:match('%s-([%+%*]?)%s+([^ ]+)')
    if not branch then
        return nil
    end
    if branch:find('^remotes/') then
        branch = branch:match('remotes/.-/(.-)$') or branch
    end
    if branch == 'HEAD' or branch == '' then
        return nil
    end
    return branch
end

---@param selected string[]?
---@return string?
local function commit_sha(selected)
    local line = selected and selected[1]
    if type(line) ~= 'string' or line == '' then
        return nil
    end
    return line:match('^(%S+)')
end

function M.open()
    M.load()
    local picker = require('forge.picker')
    local entries = {}

    for _, item in ipairs(menu_entries) do
        entries[#entries + 1] = {
            display = { { item.label } },
            value = item,
            ordinal = item.label,
        }
    end

    picker.pick({
        prompt = 'Forge> ',
        entries = entries,
        actions = {
            {
                name = 'default',
                label = 'open',
                fn = function(entry)
                    local value = entry and entry.value
                    if type(value) ~= 'table' then
                        return
                    end
                    if value.kind == 'route' then
                        M.load().open(value.route)
                        return
                    end
                    local client = fzf()
                    if value.picker == 'commits' then
                        client.git_commits()
                        return
                    end
                    if value.picker == 'buffer_commits' then
                        client.git_bcommits()
                        return
                    end
                    if value.picker == 'branches' then
                        client.git_branches()
                        return
                    end
                    if value.picker == 'worktrees' then
                        client.git_worktrees()
                        return
                    end
                    if value.picker == 'stash' then
                        client.git_stash()
                        return
                    end
                    client.git_tags()
                end,
            },
        },
        picker_name = 'forge_wrapper',
    })
end

function M.open_stock()
    M.load().open()
end

---@param selected string[]?
function M.browse_selected_branch(selected)
    local branch = branch_name(selected)
    if not branch then
        warn('cannot browse detached HEAD')
        return
    end
    M.load()
    require('forge.ops').browse_branch(branch)
end

---@param selected string[]?
function M.browse_selected_commit(selected)
    local commit = commit_sha(selected)
    if not commit then
        warn('cannot browse unknown commit')
        return
    end
    M.load()
    require('forge.ops').browse_commit({ commit = commit })
end

return M
