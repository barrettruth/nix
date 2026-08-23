local M = {}

local TIMEOUT_MS = 2000

function M.load()
    local root = vim.fs.root(vim.fn.getcwd(), '.envrc')
    if not root or vim.env.DIRENV_DIR == '-' .. root then
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
        local failed = result.code ~= 0
        local loaded = false
        for key, value in pairs(failed and {} or vim.json.decode(result.stdout)) do
            vim.env[key] = value ~= vim.NIL and value or nil
            loaded = loaded or not vim.startswith(key, 'DIRENV_')
        end

        if progress.id then
            progress.status = failed and 'error' or 'success'
            vim.api.nvim_echo({}, false, progress)
        end

        local level, msg = vim.log.levels.WARN, nil
        if failed then
            msg = ('%s failed (exit %d)'):format(name, result.code)
        elseif not loaded then
            msg = ('%s is blocked, run direnv allow'):format(name)
        elseif progress.id then
            msg = ('loaded %s, :restart to apply'):format(name)
        else
            level, msg = vim.log.levels.INFO, ('loaded %s'):format(name)
        end
        vim.notify('direnv: ' .. msg, level)
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
