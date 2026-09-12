---@class mux.Candidate
---@field root string
---@field server? mux.Server
---@field zoxide_rank? integer
---@field zoxide_paths? string[]

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

    require('zoxide').query('', true, function(output, err)
        if not output then
            cb(candidates, err)
            return
        end

        for rank, path in ipairs(vim.split(output, '\n', { trimempty = true })) do
            local root = command.resolve(path)
            if root then
                local index = indexes[root]
                if not index then
                    index = #candidates + 1
                    candidates[index] = { root = root }
                    indexes[root] = index
                end
                local candidate = candidates[index]
                candidate.zoxide_rank = candidate.zoxide_rank or rank
                candidate.zoxide_paths = candidate.zoxide_paths or {}
                candidate.zoxide_paths[#candidate.zoxide_paths + 1] = path
            end
        end

        cb(candidates)
    end)
end

---@param candidate mux.Candidate
---@param cb fun(ok?: true, err?: string)
function M.remove(candidate, cb)
    local paths = candidate.zoxide_paths or {}
    local function remove_path(index)
        if not paths[index] then
            server.remove(candidate.root, cb, candidate.server)
            return
        end
        require('zoxide').run(
            { 'remove', '--', paths[index] },
            function(output, err)
                if
                    output ~= nil
                    or (
                        err
                        and vim.startswith(err, 'path not found in database: ')
                    )
                then
                    remove_path(index + 1)
                else
                    cb(nil, err)
                end
            end
        )
    end
    remove_path(1)
end

return M
