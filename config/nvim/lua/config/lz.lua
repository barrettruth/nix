---@class config.lz
local M = {}

---@param name string
---@return string
local function pack_name(name)
    return name:match('[^/]+$') or name
end

---@overload fun(plugins: string[])
---@param plugins string|string[]
function M.load(plugins)
    if type(plugins) == 'table' then
        for _, plugin in ipairs(plugins) do
            M.load(plugin)
        end
        return
    end

    pcall(require('lz.n').trigger_load, plugins)
    vim.cmd.packadd(pack_name(plugins))
end

return M
