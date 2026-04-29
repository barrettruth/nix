---@class config.completion.Context
---@field base string
---@field before string
---@field bufnr integer
---@field col integer
---@field filetype string
---@field line string
---@field row integer

---@class config.completion.ItemUserData: table<string, any>
---@field source? string

---@class config.completion.Item
---@field word string
---@field abbr? string
---@field dup? integer
---@field icase? integer
---@field info? string
---@field kind? string
---@field menu? string
---@field user_data? config.completion.ItemUserData

---@alias config.completion.Items config.completion.Item[]

---@class config.completion.Provider
---@field source? string
---@field findstart? fun(ctx: config.completion.Context): integer?
---@field complete? fun(ctx: config.completion.Context): config.completion.Items
---@field convert_lsp_item? fun(item: table, ctx: config.completion.Context): table?
---@field on_complete_done? fun(item: config.completion.Item, ctx: config.completion.Context)

---@class config.completion.LoaderTask
---@field sync fun(): string
---@field async fun(done: fun(output: string))

---@class config.completion.Loader
---@field ensure_loaded fun()
---@field preload fun()

return {}
