---@type config.completion.Provider
local M = {
    source = 'conventional_commits',
}

local util = require('config.completion.util')

local items = {
    {
        word = 'feat',
        info = 'A new feature (MINOR in semver)',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'fix',
        info = 'A bug fix (PATCH in semver)',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'docs',
        info = 'Documentation only',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'style',
        info = 'Formatting, whitespace — no behavioral change',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'refactor',
        info = 'Restructures code without changing behavior',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'perf',
        info = 'Performance improvement',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'test',
        info = 'Add or correct tests',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'build',
        info = 'Build system or external dependencies',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'ci',
        info = 'CI/CD configuration and scripts',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'chore',
        info = 'Routine tasks outside src and test',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'revert',
        info = 'Reverts a previous commit',
        kind = 'cc',
        user_data = { source = M.source },
    },
}

local body_items = {
    {
        word = 'fixes #',
        icase = 1,
        info = 'Reference that closes an issue or pull request',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'closes #',
        icase = 1,
        info = 'Reference that closes an issue or pull request',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'refs #',
        icase = 1,
        info = 'Reference an issue or pull request without closing it',
        kind = 'cc',
        user_data = { source = M.source },
    },
    {
        word = 'BREAKING CHANGE: ',
        icase = 1,
        info = 'Describe an incompatible API or behavior change',
        kind = 'cc',
        user_data = { source = M.source },
    },
}

local type_names = {}
for _, item in ipairs(items) do
    type_names[item.word] = true
end

local generic_scopes = {
    ['.github'] = true,
    ['.gitlab'] = true,
    after = true,
    app = true,
    apps = true,
    config = true,
    configs = true,
    doc = true,
    docs = true,
    ftplugin = true,
    hosts = true,
    lib = true,
    lua = true,
    module = true,
    modules = true,
    package = true,
    packages = true,
    plugin = true,
    plugins = true,
    script = true,
    scripts = true,
    service = true,
    services = true,
    spec = true,
    specs = true,
    src = true,
    test = true,
    tests = true,
    workflow = true,
    workflows = true,
}

local scope_cache = {}
local scope_loading = {}
local root_cache = {}

---@class config.completion.conventional_commits.State
---@field base string
---@field dir string
---@field kind 'body'|'scope'|'suffix'|'type'
---@field prefix string?
---@field start integer
---@field suffixes string[]?

---@param ctx config.completion.Context
---@return string
local function git_dir(ctx)
    local path = vim.api.nvim_buf_get_name(ctx.bufnr)
    if path == '' then
        return vim.uv.cwd()
    end

    path = vim.fn.fnamemodify(path, ':p:h')
    if root_cache[path] then
        return root_cache[path]
    end

    local root = util.git_root(path)
    if root == '' then
        root = path
    end

    root_cache[path] = root
    return root
end

---@param path string
---@return string?
local function scope_candidate(path)
    path = path:match('.+ %-%> (.+)$') or path

    local first, second = path:match('^([^/]+)/([^/]+)')
    if not first then
        return
    end

    local candidate = generic_scopes[first] and second or first
    candidate = candidate:gsub('%.%w+$', ''):lower()
    if candidate == '' or generic_scopes[candidate] then
        return
    end
    if not candidate:match('^[-%w][-%w._]*$') then
        return
    end

    return candidate
end

---@param log_out string
---@param status_out string
---@return string[]
local function parse_scopes(log_out, status_out)
    local scopes = {}
    local seen = {}

    ---@param scope string?
    local function add(scope)
        if type(scope) ~= 'string' or scope == '' then
            return
        end
        if not scope:match('^[-%w][-%w._/]*$') then
            return
        end

        local key = scope:lower()
        if seen[key] then
            return
        end

        seen[key] = true
        scopes[#scopes + 1] = scope
    end

    for _, line in ipairs(util.lines(status_out)) do
        local path = line:match('^..%s+(.*)$')
        if path then
            add(scope_candidate(path))
        end
    end

    for _, line in ipairs(util.lines(log_out)) do
        add(line:match('^[%l-]+%(([^()]+)%)!?'))
    end

    return scopes
end

---@param dir string
---@return string[]
local function load_scopes_sync(dir)
    local scopes = parse_scopes(
        util.system_text({ 'git', '-C', dir, 'log', '--format=%s', '-n', '200' }),
        util.system_text({
            'git',
            '-C',
            dir,
            'status',
            '--porcelain',
            '--untracked-files=all',
        })
    )

    scope_cache[dir] = scopes
    return scopes
end

---@param dir string
---@return string[]
local function ensure_scopes(dir)
    if dir == '' then
        return {}
    end

    return scope_cache[dir] or load_scopes_sync(dir)
end

function M.preload()
    local dir = git_dir(util.context(''))
    if dir == '' or scope_cache[dir] or scope_loading[dir] then
        return
    end

    scope_loading[dir] = true

    local outputs = {}
    local remaining = 2

    local function done(index, output)
        outputs[index] = output
        remaining = remaining - 1
        if remaining ~= 0 then
            return
        end

        scope_loading[dir] = nil
        scope_cache[dir] = parse_scopes(outputs[1] or '', outputs[2] or '')
    end

    util.system_text_async(
        { 'git', '-C', dir, 'log', '--format=%s', '-n', '200' },
        function(output)
            done(1, output)
        end
    )
    util.system_text_async({
        'git',
        '-C',
        dir,
        'status',
        '--porcelain',
        '--untracked-files=all',
    }, function(output)
        done(2, output)
    end)
end

---@param ctx config.completion.Context
---@return config.completion.conventional_commits.State?
local function header_state(ctx)
    if ctx.row ~= 1 then
        return
    end

    local type_name, scope_base = ctx.before:match('^([%l-]+)%(([-%w%._/]*)$')
    if type_name and type_names[type_name] then
        return {
            base = scope_base,
            dir = git_dir(ctx),
            kind = 'scope',
            start = ctx.col - #scope_base,
        }
    end

    type_name = ctx.before:match('^([%l-]+)%([^)]*%)!$')
    if type_name and type_names[type_name] then
        return {
            base = '',
            dir = git_dir(ctx),
            kind = 'suffix',
            prefix = ctx.before,
            start = ctx.col,
            suffixes = { ': ' },
        }
    end

    type_name = ctx.before:match('^([%l-]+)!$')
    if type_name and type_names[type_name] then
        return {
            base = '',
            dir = git_dir(ctx),
            kind = 'suffix',
            prefix = ctx.before,
            start = ctx.col,
            suffixes = { ': ' },
        }
    end

    type_name = ctx.before:match('^([%l-]+)%([^)]*%)$')
    if type_name and type_names[type_name] then
        return {
            base = '',
            dir = git_dir(ctx),
            kind = 'suffix',
            prefix = ctx.before,
            start = ctx.col,
            suffixes = { ': ', '!: ' },
        }
    end

    local type_base = ctx.before:match('^([%l-]+)$')
    if type_base == nil then
        return
    end

    if type_names[type_base] then
        return {
            base = '',
            dir = git_dir(ctx),
            kind = 'suffix',
            prefix = ctx.before,
            start = ctx.col,
            suffixes = { ': ', '(', '!: ' },
        }
    end

    return {
        base = type_base,
        dir = git_dir(ctx),
        kind = 'type',
        start = ctx.col - #type_base,
    }
end

---@param ctx config.completion.Context
---@return config.completion.conventional_commits.State?
local function body_state(ctx)
    if ctx.row == 1 then
        return
    end

    local base = ctx.before:match('^%s*(.-)$') or ''
    if base:find('[^%a%-%s]') then
        return
    end

    local first = ctx.before:find('%S') or (ctx.col + 1)
    return {
        base = base,
        dir = git_dir(ctx),
        kind = 'body',
        start = first - 1,
    }
end

---@param base string
---@return config.completion.conventional_commits.State?
local function context(base)
    local ctx = util.context(base)
    if ctx.filetype ~= 'gitcommit' or ctx.before:match('^%s*#') then
        return
    end

    return header_state(ctx) or body_state(ctx)
end

---@param base string
---@param dir string
---@return config.completion.Items
local function complete_scopes(base, dir)
    local words = {}

    for _, scope in ipairs(util.filter_strings(ensure_scopes(dir), base, true)) do
        words[#words + 1] = {
            word = scope .. ')',
            abbr = scope,
            icase = 1,
            info = 'Insert scope and close it',
            kind = 'cc',
            user_data = { source = M.source },
        }
    end

    return words
end

---@param prefix string?
---@param suffixes string[]
---@return config.completion.Items
local function complete_suffixes(prefix, suffixes)
    local words = {}

    for _, suffix in ipairs(suffixes) do
        local info = suffix == '(' and 'Add an optional scope'
            or suffix == '!: ' and 'Mark the change as breaking and start the subject'
            or 'Start the subject'

        words[#words + 1] = {
            word = suffix,
            abbr = (prefix or '') .. suffix,
            info = info,
            kind = 'cc',
            user_data = { source = M.source },
        }
    end

    return words
end

---@param findstart integer
---@param base string
---@return integer|config.completion.Items
function M.complete(findstart, base)
    local ctx = context(base)
    if findstart == 1 then
        return ctx and ctx.start or -2
    end

    if not ctx then
        return {}
    end

    if ctx.kind == 'type' then
        return util.filter_items(items, ctx.base)
    end
    if ctx.kind == 'scope' then
        return complete_scopes(ctx.base, ctx.dir)
    end
    if ctx.kind == 'suffix' then
        return complete_suffixes(ctx.prefix, ctx.suffixes or {})
    end

    return util.filter_items(body_items, ctx.base)
end

M.omnifunc = M.complete

return M
