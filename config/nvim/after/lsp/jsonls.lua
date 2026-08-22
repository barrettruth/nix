return {
    capabilities = {
        textDocument = {
            completion = {
                completionItem = { snippetSupport = true },
            },
        },
    },
    settings = {
        json = {
            validate = { enable = true },
        },
    },
}
