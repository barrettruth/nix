local M = {}

local conventional = require('config.completion.conventional_commits')
local filetype = require('config.completion.filetype')
local forge_refs = require('config.completion.forge_refs')
local git_log = require('config.completion.git_log')
local util = require('config.completion.util')

---@type { detect: fun(ctx: config.completion.Context): any?, complete: fun(findstart: integer, base: string): integer|config.completion.Items }[]
local providers = {
    {
        detect = forge_refs.context_at_cursor,
        complete = forge_refs.complete_omnifunc,
    },
    {
        detect = git_log.context_at_cursor,
        complete = git_log.complete_omnifunc,
    },
}

---@param findstart integer
---@param base string
---@return integer|config.completion.Items
function M.complete(findstart, base)
    local ctx = util.context(base)
    for _, p in ipairs(providers) do
        if p.detect(ctx) then
            return p.complete(findstart, base)
        end
    end
    return conventional.complete(findstart, base)
end

function M.setup()
    filetype.setup(
        "v:lua.require'config.completion.gitcommit'.complete",
        function()
            conventional.preload()
            vim.schedule(function()
                forge_refs.warmup(0)
            end)
            vim.schedule(function()
                git_log.warmup(0)
            end)
        end
    )
end

return M
