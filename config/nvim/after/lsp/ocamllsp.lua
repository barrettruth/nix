return {
    cmd = { 'ocamllsp' },
    filetypes = { 'ocaml', 'dune' },
    root_markers = {
        'dune-project',
        'dune-workspace',
        '*.opam',
        '.git',
    },
}
