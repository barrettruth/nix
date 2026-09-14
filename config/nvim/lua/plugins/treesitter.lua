vim.pack.add({
    {
        src = 'https://github.com/nvim-treesitter/nvim-treesitter',
        version = 'main',
    },
    'https://github.com/nvim-treesitter/nvim-treesitter-textobjects',
    'https://github.com/Wansmer/treesj',
})

vim.treesitter.language.register('starlark', 'bzl')

local ts = require('nvim-treesitter')
ts.setup({ install_dir = vim.fn.stdpath('data') .. '/treesitter' })

local group = vim.api.nvim_create_augroup('ATreesitter', { clear = true })
local pending = {}

local function language(buf)
    if not vim.api.nvim_buf_is_loaded(buf) then
        return
    end
    local bt = vim.bo[buf].buftype
    if bt == 'terminal' or bt == 'prompt' or bt == 'quickfix' then
        return
    end
    local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
    local parser = lang and require('nvim-treesitter.parsers')[lang]
    return parser and parser.tier ~= 4 and lang or nil
end

local function ready(lang)
    local installed = ts.get_installed()
    for _, dependency in
        ipairs(require('nvim-treesitter.config').norm_languages({ lang }))
    do
        if not vim.list_contains(installed, dependency) then
            return false
        end
    end
    return true
end

---@param buf integer
---@param lang string
local function start(buf, lang)
    if language(buf) == lang and not vim.treesitter.highlighter.active[buf] then
        pcall(function()
            local parser = vim.treesitter.get_parser(buf, lang)
            if parser then
                parser:invalidate(true)
                vim.treesitter.start(buf, lang)
            end
        end)
    end
end

local function refresh()
    vim.treesitter.query.get:clear()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local lang = language(buf)
        if lang and ready(lang) then
            vim.treesitter.stop(buf)
            start(buf, lang)
        end
    end
    vim.cmd.redraw()
end

local installer = require('nvim-treesitter.install')
for _, action in ipairs({ 'install', 'update' }) do
    local operation = installer[action]
    installer[action] = function(...)
        local task = operation(...)
        task:await(vim.schedule_wrap(function(err, success)
            if err or success == false then
                vim.notify(
                    'Tree-sitter ' .. action .. ' failed; see :TSLog',
                    vim.log.levels.ERROR
                )
            end
            refresh()
        end))
        return task
    end
end

local function ensure(buf)
    local lang = language(buf)
    local active = vim.treesitter.highlighter.active[buf]
    if active and active.tree:lang() ~= lang then
        vim.treesitter.stop(buf)
    end
    if not lang then
        return
    end
    if ready(lang) then
        start(buf, lang)
    elseif not pending[lang] then
        local task = ts.install({ lang })
        pending[lang] = task
        task:await(function()
            pending[lang] = nil
        end)
    end
end

vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(ev)
        ensure(ev.buf)
    end,
})
vim.api.nvim_create_autocmd('PackChanged', {
    group = group,
    callback = function(ev)
        if
            ev.data.spec.name == 'nvim-treesitter'
            and ev.data.kind == 'update'
        then
            ts.update()
        end
    end,
})
vim.schedule(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        ensure(buf)
    end
end)

return {
    {
        'nvim-treesitter/nvim-treesitter-textobjects',
        after = function()
            require('nvim-treesitter-textobjects').setup({
                select = {
                    enable = true,
                    lookahead = true,
                },
                move = {
                    enable = true,
                    set_jumps = true,
                },
            })

            local select = require('nvim-treesitter-textobjects.select')
            local select_maps = {
                { 'aa', '@parameter.outer' },
                { 'ia', '@parameter.inner' },
                { 'as', '@class.outer' },
                { 'is', '@class.inner' },
                { 'aC', '@call.outer' },
                { 'iC', '@call.inner' },
                { 'af', '@function.outer' },
                { 'if', '@function.inner' },
                { 'ai', '@conditional.outer' },
                { 'ii', '@conditional.inner' },
                { 'aL', '@loop.outer' },
                { 'iL', '@loop.inner' },
            }
            for _, m in ipairs({ 'x', 'o' }) do
                for _, t in ipairs(select_maps) do
                    vim.keymap.set(m, t[1], function()
                        select.select_textobject(t[2], 'textobjects', m)
                    end, { desc = 'select ' .. t[2] })
                end
            end

            local incremental_select = require('vim.treesitter._select')
            vim.keymap.set('x', '+', function()
                if vim.treesitter.get_parser(nil, nil, { error = false }) then
                    incremental_select.select_parent(vim.v.count1)
                else
                    vim.lsp.buf.selection_range(vim.v.count1)
                end
            end, { desc = 'expand selection' })
            vim.keymap.set('x', '-', function()
                if vim.treesitter.get_parser(nil, nil, { error = false }) then
                    incremental_select.select_child(vim.v.count1)
                else
                    vim.lsp.buf.selection_range(-vim.v.count1)
                end
            end, { desc = 'shrink selection' })

            local move = require('nvim-treesitter-textobjects.move')
            local move_textobjects = {
                { 'a', '@parameter.inner' },
                { 's', '@class.outer' },
                { 'f', '@function.outer' },
                { 'i', '@conditional.outer' },
                { '/', '@comment.outer' },
            }
            for _, m in ipairs({ 'n', 'x', 'o' }) do
                for _, t in ipairs(move_textobjects) do
                    local key, capture = t[1], t[2]
                    vim.keymap.set(m, ']' .. key, function()
                        move.goto_next_start(capture, 'textobjects')
                    end, {
                        desc = 'next ' .. capture .. ' start',
                    })
                    vim.keymap.set(m, '[' .. key, function()
                        move.goto_previous_start(capture, 'textobjects')
                    end, {
                        desc = 'prev ' .. capture .. ' start',
                    })
                    local upper = key:upper()
                    if upper ~= key then
                        vim.keymap.set(m, ']' .. upper, function()
                            move.goto_next_end(capture, 'textobjects')
                        end, {
                            desc = 'next ' .. capture .. ' end',
                        })
                        vim.keymap.set(m, '[' .. upper, function()
                            move.goto_previous_end(capture, 'textobjects')
                        end, {
                            desc = 'prev ' .. capture .. ' end',
                        })
                    end
                end
            end

            local ts_repeat =
                require('nvim-treesitter-textobjects.repeatable_move')
            for _, m in ipairs({ 'n', 'x', 'o' }) do
                vim.keymap.set(
                    m,
                    ';',
                    ts_repeat.repeat_last_move_next,
                    { desc = 'repeat last move next' }
                )
                vim.keymap.set(
                    m,
                    ',',
                    ts_repeat.repeat_last_move_previous,
                    { desc = 'repeat last move prev' }
                )
                vim.keymap.set(
                    m,
                    'f',
                    ts_repeat.builtin_f_expr,
                    { expr = true, desc = 'repeatable f' }
                )
                vim.keymap.set(
                    m,
                    'F',
                    ts_repeat.builtin_F_expr,
                    { expr = true, desc = 'repeatable F' }
                )
                vim.keymap.set(
                    m,
                    't',
                    ts_repeat.builtin_t_expr,
                    { expr = true, desc = 'repeatable t' }
                )
                vim.keymap.set(
                    m,
                    'T',
                    ts_repeat.builtin_T_expr,
                    { expr = true, desc = 'repeatable T' }
                )
            end
        end,
    },
    {
        'Wansmer/treesj',
        after = function()
            require('treesj').setup({ use_default_keymaps = false })
        end,
        keys = {
            { 'gt', '<cmd>TSJToggle<cr>', desc = 'toggle split/join' },
        },
    },
}
