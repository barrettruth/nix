local ok, schemastore = pcall(require, 'schemastore')
local json = {
    validate = { enable = true },
}
if ok then
    json.schemas = schemastore.json.schemas()
end

return {
    capabilities = {
        textDocument = {
            completion = {
                completionItem = { snippetSupport = true },
            },
        },
    },
    settings = {
        json = json,
    },
}
