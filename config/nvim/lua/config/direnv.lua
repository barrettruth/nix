local M = {}

local TIMEOUT_MS = 500

function M.load()
    local root = vim.fs.root(vim.fn.getcwd(), '.envrc')
    if not root or (vim.env.DIRENV_DIR or ''):sub(2) == root then
        return
    end

    local done = false
    vim.system({ 'direnv', 'export', 'json' }, {
        cwd = root,
        env = { DIRENV_LOG_FORMAT = '' },
        text = true,
    }, function(result)
        vim.schedule(function()
            done = true
            if result.code ~= 0 then
                return
            end
            local ok, env = pcall(vim.json.decode, result.stdout or '')
            if not ok or type(env) ~= 'table' then
                return
            end
            for key, value in pairs(env) do
                vim.env[key] = value ~= vim.NIL and value or nil
            end
        end)
    end)
    vim.wait(TIMEOUT_MS, function()
        return done
    end)
end

function M.setup()
    vim.api.nvim_create_autocmd('DirChanged', {
        group = vim.api.nvim_create_augroup('Direnv', { clear = true }),
        callback = M.load,
    })
    M.load()
end

return M
