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
---@field forge? config.completion.ForgeItemData
---@field git_log? config.completion.GitLogItemData

---@class config.completion.ForgeItemData
---@field backend config.completion.forge.BackendName
---@field host string
---@field owner string
---@field repo string
---@field key string
---@field kind 'issue'|'pr'|'mr'|'mention'
---@field number? integer
---@field login? string

---@class config.completion.GitLogItemData
---@field root string
---@field sha string

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
---@field on_complete_done? fun(item: config.completion.Item, ctx: config.completion.Context)

---@class config.completion.LoaderTask
---@field sync fun(): string
---@field async fun(done: fun(output: string))

---@class config.completion.LoaderOpts
---@field loaded fun(): boolean
---@field store fun(outputs: string[])
---@field tasks config.completion.LoaderTask[]
---@field wait_timeout? integer

---@class config.completion.Loader
---@field ensure_loaded fun()
---@field preload fun()

---@alias config.completion.forge.BackendName 'github'|'gitlab'|'gitea'

---@alias config.completion.forge.Trigger '#'|'@'|'!'

---@alias config.completion.forge.RefKind 'issue'|'pr'|'mr'

---@class config.completion.forge.Repo
---@field backend config.completion.forge.BackendName
---@field host string
---@field owner string
---@field repo string
---@field key string

---@class config.completion.forge.RefItem
---@field kind config.completion.forge.RefKind
---@field number integer
---@field title string
---@field state 'open'|'closed'|'merged'
---@field updated? integer
---@field url? string
---@field draft? boolean

---@class config.completion.forge.MentionItem
---@field login string
---@field name? string
---@field source 'assignee'|'contributor'|'collaborator'|'project_user'

---Backend adapter contract. Each adapter owns one CLI (`gh`/`glab`/`tea`)
---and one or more hosts. The registry routes hosts to adapters via
---`hosts` (literal match) and/or `matches_host` (custom predicate, e.g.
---for GHE/self-hosted Gitea where the host list isn't fixed).
---
---Bucket names are backend-defined strings keyed by trigger char in
---`bucket_for_trigger`. Common buckets are `'refs'`, `'mrs'`, `'mentions'`.
---`fetch`, `fetch_exact`, and `fetch_doc` are uniform entrypoints that
---internally dispatch on the bucket name; this keeps `forge_refs.lua`
---generic over the bucket count and shape per backend.
---@class config.completion.forge.Backend
---@field name config.completion.forge.BackendName
---@field cli? string
---@field hosts string[]
---@field matches_host? fun(host: string): boolean
---@field triggers config.completion.forge.Trigger[]
---@field bucket_for_trigger table<config.completion.forge.Trigger, string>
---@field fetch fun(bucket: string, repo: config.completion.forge.Repo, cb: fun(items: any?, err: string?))
---@field fetch_exact fun(bucket: string, repo: config.completion.forge.Repo, n: integer, cb: fun(item: any?, err: string?))
---@field fetch_doc fun(bucket: string, repo: config.completion.forge.Repo, n: integer, cb: fun(body: string?, err: string?))

---@class config.completion.git_log.Commit
---@field sha string
---@field short string
---@field subject string

---@class config.completion.git_log.TokenContext
---@field bufnr integer
---@field row integer
---@field start_col integer
---@field end_col integer
---@field base string
---@field strong_context boolean

---@class config.completion.forge.TokenContext
---@field bufnr integer
---@field row integer
---@field start_col integer
---@field end_col integer
---@field trigger config.completion.forge.Trigger
---@field base string
---@field cross_repo? { owner: string, repo: string }

return {}
