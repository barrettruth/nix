local M = {}

local function make_source(def)
    local src = {}

    function src.new()
        local self = setmetatable({}, { __index = src })
        local Kind = require('blink.cmp.types').CompletionItemKind
        self.Kind = Kind
        self.items = def.items(Kind)
        return self
    end

    src.enabled = def.enabled
    src.get_completions = def.get_completions
        or function(self, _, callback)
            callback({
                is_incomplete_forward = false,
                is_incomplete_backward = false,
                items = vim.deepcopy(self.items),
            })
        end

    return src
end

M.conventional_commits = make_source({
    enabled = function()
        return vim.tbl_contains(
            { 'gitcommit', 'octo', 'markdown' },
            vim.bo.filetype
        )
    end,
    items = function(Kind)
        local types = {
            { 'feat', 'A new feature (MINOR in semver)' },
            { 'fix', 'A bug fix (PATCH in semver)' },
            { 'docs', 'Documentation only' },
            { 'style', 'Formatting, whitespace — no behavioral change' },
            { 'refactor', 'Restructures code without changing behavior' },
            { 'perf', 'Performance improvement' },
            { 'test', 'Add or correct tests' },
            { 'build', 'Build system or external dependencies' },
            { 'ci', 'CI/CD configuration and scripts' },
            { 'chore', 'Routine tasks outside src and test' },
            { 'revert', 'Reverts a previous commit' },
        }
        local out = {}
        for _, t in ipairs(types) do
            out[#out + 1] = {
                label = t[1],
                kind = Kind.Keyword,
                documentation = { kind = 'markdown', value = t[2] },
            }
        end
        return out
    end,
    get_completions = function(self, ctx, callback)
        local row, col = unpack(ctx.cursor)
        local before = ctx.line:sub(1, col)

        if not before:find('%s') then
            if row > 1 then
                local item = {
                    label = 'BREAKING CHANGE',
                    kind = self.Kind.Keyword,
                    documentation = {
                        kind = 'markdown',
                        value = 'Adds a `BREAKING CHANGE` footer and marks the commit header with `!`.',
                    },
                }
                local first = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
                if not first:match('!:') then
                    local colon = first:find(':')
                    if colon then
                        item.additionalTextEdits = {
                            {
                                range = {
                                    start = { line = 0, character = colon - 1 },
                                    ['end'] = { line = 0, character = colon - 1 },
                                },
                                newText = '!',
                            },
                        }
                    end
                end
                callback({ items = { item } })
                return
            elseif not before:find('[():]') then
                callback({
                    is_incomplete_forward = false,
                    is_incomplete_backward = false,
                    items = vim.deepcopy(self.items),
                })
                return
            end
        end

        callback({ items = {} })
    end,
})

for name, src in pairs(M) do
    package.loaded['config.blink.' .. name] = src
end

return M
