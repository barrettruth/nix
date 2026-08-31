---@class mux.Candidate
---@field root string
---@field server? mux.Server
---@field zoxide_rank? integer

---@alias mux.CandidatesCallback fun(candidates: mux.Candidate[], err?: string)

local command = require('mux.command')
local server = require('mux.server')

local M = {}

---@param cb mux.CandidatesCallback
function M.list(cb)
    local known, can_discover_local = server.list()
    local candidates = {}
    local indexes = {}

    table.sort(known, function(a, b)
        return a.root < b.root
    end)

    for _, target in ipairs(known) do
        candidates[#candidates + 1] = {
            root = target.root,
            server = target,
        }
        indexes[target.root] = #candidates
    end

    if not can_discover_local then
        vim.schedule(function()
            cb(candidates)
        end)
        return
    end

    local ok, proc = pcall(vim.system, {
        'zoxide',
        'query',
        '--list',
    }, { text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                local err = vim.trim(result.stderr or '')
                if err == '' then
                    err = 'zoxide exited ' .. result.code
                end
                cb(candidates, err)
                return
            end

            for rank, path in
                ipairs(
                    vim.split(result.stdout or '', '\n', { trimempty = true })
                )
            do
                local root = command.resolve(path)
                if root then
                    local index = indexes[root]
                    if index then
                        candidates[index].zoxide_rank = candidates[index].zoxide_rank
                            or rank
                    else
                        candidates[#candidates + 1] = {
                            root = root,
                            zoxide_rank = rank,
                        }
                        indexes[root] = #candidates
                    end
                end
            end

            cb(candidates)
        end)
    end)

    if not ok then
        vim.schedule(function()
            cb(candidates, tostring(proc))
        end)
    end
end

return M
