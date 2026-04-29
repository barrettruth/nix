local M = {}

---@param omnifunc string
---@param preload? fun()
function M.setup(omnifunc, preload)
    vim.opt_local.complete = { 'o', '.', 'w', 'b' }
    vim.bo.omnifunc = omnifunc

    if preload then
        preload()
    end
end

return M
