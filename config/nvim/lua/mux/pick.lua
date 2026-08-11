local M = {}

---Pick a mux session and connect to it.
---@return nil
function M.sessions()
    local server = require('mux.server')
    local current = server.state().server
    if not current then
        vim.notify('mux: not a mux server', vim.log.levels.ERROR)
        return
    end
    vim.ui.select(require('mux.line').servers(), {
        prompt = 'Select a session:',
        kind = 'mux.session',
        format_item = function(entry)
            return (entry.root == current.root and '*' or '')
                .. vim.fn.fnamemodify(entry.root, ':t')
        end,
    }, function(choice)
        if not choice or choice.root == current.root then
            return
        end
        server.connect(choice.root, function(ok, err)
            if not ok then
                vim.notify('mux: ' .. tostring(err), vim.log.levels.ERROR)
            end
        end)
    end)
end

return M
