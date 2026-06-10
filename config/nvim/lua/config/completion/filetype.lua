local M = {}

---@param omnifunc string `v:lua`-style omnifunc expression
---@param preload? fun() warm cache
function M.setup(omnifunc, preload)
    vim.opt_local.complete = { 'o', '.', 'w', 'b' }
    vim.bo.omnifunc = omnifunc

    if preload then
        preload()
    end
end

return M
