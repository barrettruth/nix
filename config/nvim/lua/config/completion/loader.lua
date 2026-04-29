local M = {}

---@param tasks config.completion.LoaderTask[]
---@return string[]
local function collect_sync(tasks)
    local outputs = {}

    for i, task in ipairs(tasks) do
        outputs[i] = task.sync()
    end

    return outputs
end

---@param tasks config.completion.LoaderTask[]
---@param callback fun(outputs: string[])
local function collect_async(tasks, callback)
    local outputs = {}
    local remaining = #tasks

    if remaining == 0 then
        callback(outputs)
        return
    end

    local function done(index, output)
        outputs[index] = output
        remaining = remaining - 1
        if remaining == 0 then
            callback(outputs)
        end
    end

    for i, task in ipairs(tasks) do
        task.async(function(output)
            done(i, output)
        end)
    end
end

---@param opts { loaded: fun(): boolean, store: fun(outputs: string[]), tasks: config.completion.LoaderTask[], wait_timeout?: integer }
---@return config.completion.Loader
function M.new(opts)
    local loading = false
    local wait_timeout = opts.wait_timeout or 100

    local function store(outputs)
        loading = false
        opts.store(outputs)
    end

    return {
        ensure_loaded = function()
            if opts.loaded() then
                return
            end

            if loading then
                vim.wait(wait_timeout, opts.loaded, 20)
            end

            if opts.loaded() then
                return
            end

            loading = false
            opts.store(collect_sync(opts.tasks))
        end,
        preload = function()
            if opts.loaded() or loading then
                return
            end

            loading = true
            collect_async(opts.tasks, store)
        end,
    }
end

return M
