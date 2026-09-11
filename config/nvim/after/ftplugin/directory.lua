vim.opt_local.bufhidden = 'wipe'

vim.keymap.set('n', 'g.', function()
    vim.b.dir_git_visible = not vim.b.dir_git_visible
    vim.api.nvim_feedkeys(vim.keycode('<Plug>(nvim-dir-reload)'), 'm', false)
end, {
    buffer = true,
    desc = 'toggle git-visible entries',
})

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl bh<'
    .. '\nsil! nunmap <buffer> g.'
    .. '\nunlet! b:dir_git_visible'

for _, mapping in ipairs({
    { 'd', '!rm -- %s', 'delete entry' },
    { 'r', '!mv -n -- %s %s', 'rename or move entry' },
    { 'c', '!cp -n -- %s %s', 'copy entry' },
    { 't', '!touch -- ', 'touch file' },
    { 'm', 'Mkdir ', 'create directory' },
    { 'x', 'Chmod +x %s', 'change permissions' },
}) do
    local key, template, desc = unpack(mapping)
    vim.keymap.set('n', key, function()
        local name =
            vim.api.nvim_get_current_line():gsub('/$', ''):gsub('%z', '\n')
        if name == '' and key ~= 't' and key ~= 'm' then
            return
        end
        if
            key == 'd'
            and vim.fn.confirm(
                    'Delete ' .. vim.fn.strtrans(name) .. '?',
                    '&Yes\n&No',
                    2
                )
                ~= 1
        then
            return
        end

        local path = key == 'x' and vim.fn.fnameescape('./' .. name)
            or vim.fn.shellescape(name, true)
        local command = template:format(path, path)
        local pos = (key == 'r' or key == 'c') and #command or #command + 1
        vim.api.nvim_create_autocmd('CmdlineEnter', {
            pattern = ':',
            once = true,
            callback = function()
                vim.fn.setcmdline(command, pos)
            end,
        })
        vim.api.nvim_feedkeys(':', 'ni', false)
    end, { buffer = true, desc = desc })
    vim.b.undo_ftplugin = vim.b.undo_ftplugin
        .. '\nsil! nunmap <buffer> '
        .. key
end
