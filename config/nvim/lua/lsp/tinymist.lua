return {
    filetypes = { 'typst' },
    settings = {
        formatterMode = 'typstyle',
        exportPdf = 'onSave',
        semanticTokens = 'disable',
        lint = {
            enabled = true,
            when = 'onType',
        },
    },
}
