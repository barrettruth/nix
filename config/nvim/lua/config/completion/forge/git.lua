local M = {}

local util = require('config.completion.util')

local TIMEOUT_LOG = 1500
local TIMEOUT_SHOW = 1500
local TIMEOUT_RESOLVE = 1000

local LOG_LIMIT = 1000

---@param result vim.SystemCompleted
---@return string?
local function classify_error(result)
    if result.code == 124 then
        return 'timeout'
    end
    if result.code ~= 0 then
        return 'unavailable'
    end
    return nil
end

---@param dir string
---@return string
function M.git_root(dir)
    return util.git_root(dir)
end

---@param root string
---@param cb fun(items: config.completion.git_log.Commit[]?, err: string?)
function M.fetch_log(root, cb)
    local cmd = {
        'git',
        '-C',
        root,
        'log',
        '-n',
        tostring(LOG_LIMIT),
        '--no-merges',
        '--pretty=format:%H%x09%s',
    }
    vim.system(cmd, { text = true, timeout = TIMEOUT_LOG }, function(result)
        local err = classify_error(result)
        if err then
            vim.schedule(function()
                cb(nil, err)
            end)
            return
        end
        local stdout = result.stdout or ''
        local commits = {}
        for line in (stdout .. '\n'):gmatch('([^\n]+)') do
            local sha, subject = line:match('^([0-9a-fA-F]+)\t(.*)$')
            if sha then
                subject = (subject or ''):gsub('%s+$', '')
                commits[#commits + 1] = {
                    sha = sha,
                    short = sha:sub(1, 7),
                    subject = subject,
                }
            end
        end
        vim.schedule(function()
            cb(commits, nil)
        end)
    end)
end

---@param root string
---@param sha string
---@param cb fun(commit: config.completion.git_log.Commit?, err: string?)
function M.resolve(root, sha, cb)
    local cmd = {
        'git',
        '-C',
        root,
        'log',
        '-1',
        '--pretty=format:%H%x09%s',
        sha,
        '--',
    }
    vim.system(cmd, { text = true, timeout = TIMEOUT_RESOLVE }, function(result)
        local err = classify_error(result)
        if err then
            vim.schedule(function()
                cb(nil, err)
            end)
            return
        end
        local line = vim.trim(result.stdout or '')
        if line == '' then
            vim.schedule(function()
                cb(nil, 'missing')
            end)
            return
        end
        local full, subject = line:match('^([0-9a-fA-F]+)\t(.*)$')
        if not full then
            vim.schedule(function()
                cb(nil, 'parse')
            end)
            return
        end
        subject = (subject or ''):gsub('[\r\n\t]', ' '):gsub('%s+$', '')
        vim.schedule(function()
            cb({ sha = full, short = full:sub(1, 7), subject = subject }, nil)
        end)
    end)
end

---@param root string
---@param sha string
---@param cb fun(body: string?, err: string?)
function M.fetch_show(root, sha, cb)
    local fmt = '%H%n%an <%ae>%n%aI%n%n%s%n%n%b'
    local cmd = {
        'git',
        '-C',
        root,
        'show',
        '-s',
        '--format=' .. fmt,
        sha,
    }
    vim.system(cmd, { text = true, timeout = TIMEOUT_SHOW }, function(result)
        local err = classify_error(result)
        if err then
            vim.schedule(function()
                cb(nil, err)
            end)
            return
        end
        local body = result.stdout or ''
        body = body:gsub('\r\n', '\n'):gsub('%s+$', '')
        vim.schedule(function()
            cb(body, nil)
        end)
    end)
end

return M
