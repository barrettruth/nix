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

local source = {}

function source.new()
    local self = setmetatable({}, { __index = source })
    self.Kind = require('blink.cmp.types').CompletionItemKind
    self.items = {}
    for _, t in ipairs(types) do
        self.items[#self.items + 1] = {
            label = t[1],
            kind = self.Kind.Keyword,
            documentation = {
                kind = 'markdown',
                value = t[2]
            },
        }
    end
    return self
end

function source:enabled()
    return vim.tbl_contains({ 'gitcommit', 'octo', 'markdown' }, vim.bo.filetype)
end

function source:get_completions(ctx, callback)
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
end

return source
