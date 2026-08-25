vim.filetype.add({
    extension = {
        bazelrc = 'bazelrc',
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
