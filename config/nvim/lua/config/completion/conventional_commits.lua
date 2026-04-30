---@type config.completion.Provider
local M = {
    source = 'conventional_commits',
}

local util = require('config.completion.util')

local items = {
    {
        word = 'feat',
        info = 'A new feature (MINOR in semver)',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'fix',
        info = 'A bug fix (PATCH in semver)',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'docs',
        info = 'Documentation only',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'style',
        info = 'Formatting, whitespace — no behavioral change',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'refactor',
        info = 'Restructures code without changing behavior',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'perf',
        info = 'Performance improvement',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'test',
        info = 'Add or correct tests',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'build',
        info = 'Build system or external dependencies',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'ci',
        info = 'CI/CD configuration and scripts',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'chore',
        info = 'Routine tasks outside src and test',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'revert',
        info = 'Reverts a previous commit',
        kind = 'cc',
        user_data = { source = M.source },
    },
}
---@param ctx config.completion.Context
---@return boolean

local function active(ctx)
    return ctx.filetype == 'gitcommit'
        and ctx.row == 1
        and not ctx.before:find('%s')
        and not ctx.before:find('[():]')
end

---@param ctx config.completion.Context
---@return integer?
function M.findstart(ctx)
    if not active(ctx) then
        return
    end

    local start = ctx.col
    while start > 0 and ctx.before:sub(start, start):match('[%l-]') do
        start = start - 1
    end
    return start
end

---@param ctx config.completion.Context
---@return config.completion.Items
function M.complete(ctx)
    if not active(ctx) then
        return {}
    end

    return util.filter_items(items, ctx.base)
end

---@param findstart integer
---@param base string
---@return integer|config.completion.Items
function M.omnifunc(findstart, base)
    local ctx = util.context(base)
    if findstart == 1 then
        return M.findstart(ctx) or -2
    end

    return M.complete(ctx)
end

return M
