local M = {}

local TIMEOUT_MS = 2000

function M.load()
    local root = vim.fs.root(vim.fn.getcwd(), '.envrc')
    if not root or (vim.env.DIRENV_DIR or ''):sub(2) == root then
        return
    end

    local name = vim.fn.fnamemodify(root, ':t')
    local progress = {
        kind = 'progress',
        source = 'direnv',
        title = 'direnv',
        status = 'running',
    }
    local result

    local function finish()
        local ok, env = false, nil
        if result.code == 0 then
            ok, env = pcall(vim.json.decode, result.stdout or '')
        end
        ok = ok and type(env) == 'table'

        if progress.id then
            progress.status = ok and 'success' or 'error'
            vim.api.nvim_echo({
                { (ok and 'loaded ' or 'failed ') .. name },
            }, true, progress)
        end

        if not ok then
            vim.notify(
                ('direnv: %s failed (exit %d)'):format(name, result.code),
                vim.log.levels.WARN
            )
            return
        end

        local loaded = false
        for key, value in pairs(env) do
            vim.env[key] = value ~= vim.NIL and value or nil
            loaded = loaded or not vim.startswith(key, 'DIRENV_')
        end

        if next(env) and not loaded then
            vim.notify(
                ('direnv: %s is blocked, run direnv allow'):format(name),
                vim.log.levels.WARN
            )
        elseif loaded and progress.id then
            vim.notify(
                'direnv: environment loaded, :restart to apply',
                vim.log.levels.WARN
            )
        end
    end

    vim.system({ 'direnv', 'export', 'json' }, {
        cwd = root,
        env = { DIRENV_LOG_FORMAT = '' },
        text = true,
    }, function(completed)
        result = completed
        if progress.id then
            vim.schedule(finish)
        end
    end)

    vim.wait(TIMEOUT_MS, function()
        return result ~= nil
    end, nil, true)
    if result then
        finish()
    else
        progress.id =
            vim.api.nvim_echo({ { 'loading ' .. name } }, true, progress)
    end
end

function M.setup()
    vim.api.nvim_create_autocmd('DirChanged', {
        group = vim.api.nvim_create_augroup('Direnv', { clear = true }),
        callback = M.load,
    })
    M.load()
end

return M
