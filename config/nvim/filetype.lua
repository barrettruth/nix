vim.filetype.add({
    extension = {
        log = 'log',
        mdx = 'mdx',
    },
    filename = {
        ['requirements.txt'] = 'config',
        ['.ocamlformat'] = 'conf',
        dunstrc = 'dosini',
    },
    pattern = {
        ['.*%.in'] = function(path)
            return require('config.cp').is_cp_path(path) and 'cpinput' or nil
        end,
    },
})
