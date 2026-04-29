local M = {}

local items = {
    {
        word = 'feat',
        info = 'A new feature (MINOR in semver)',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'fix',
        info = 'A bug fix (PATCH in semver)',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'docs',
        info = 'Documentation only',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'style',
        info = 'Formatting, whitespace — no behavioral change',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'refactor',
        info = 'Restructures code without changing behavior',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'perf',
        info = 'Performance improvement',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'test',
        info = 'Add or correct tests',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'build',
        info = 'Build system or external dependencies',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'ci',
        info = 'CI/CD configuration and scripts',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'chore',
        info = 'Routine tasks outside src and test',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
    {
        word = 'revert',
        info = 'Reverts a previous commit',
        menu = '[cc]',
        user_data = { source = 'conventional_commits' },
    },
}

local function active(ctx)
    return ctx.filetype == 'gitcommit'
        and ctx.row == 1
        and not ctx.before:find('%s')
        and not ctx.before:find('[():]')
end

function M.findstart(ctx)
    if not active(ctx) then
        return
    end

    local start = ctx.col
    while start > 0 and ctx.before:sub(start, start):match('[%l-]') do
        start = start - 1
    end
    return start
end

function M.complete(ctx)
    if not active(ctx) then
        return {}
    end

    local words = {}
    for _, item in ipairs(items) do
        if ctx.base == '' or item.word:sub(1, #ctx.base) == ctx.base then
            words[#words + 1] = item
        end
    end
    return words
end

return M
