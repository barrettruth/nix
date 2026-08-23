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
})
