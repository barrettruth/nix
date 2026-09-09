local ns = vim.api.nvim_create_namespace('dir_classify')
local glyph = { fifo = '|', socket = '=', char = '%', block = '#' }
local git_cache = vim.ringbuf(16)
local git_cache_ttl = 3e9
local git_failure_ttl = 1e9
local git_cache_max_names = 2048
local git_cache_max_weight = 256 * 1024

local function cache_get(dir, mtime)
    local now = vim.uv.hrtime()
    local entries = {}
    local hit
    for entry in git_cache do
        if entry.expires > now then
            if entry.dir == dir then
                if
                    entry.mtime_sec == mtime.sec
                    and entry.mtime_nsec == mtime.nsec
                then
                    hit = entry
                end
            else
                entries[#entries + 1] = entry
            end
        end
    end
    if hit then
        entries[#entries + 1] = hit
    end
    for _, entry in ipairs(entries) do
        git_cache:push(entry)
    end
    return hit
end

local function cache_put(dir, mtime, visible, ttl)
    git_cache:push({
        dir = dir,
        mtime_sec = mtime.sec,
        mtime_nsec = mtime.nsec,
        expires = vim.uv.hrtime() + ttl,
        visible = visible,
    })
end

local function git_visible(dir)
    local stat = vim.uv.fs_stat(dir)
    if not stat then
        return false
    end

    local cached = cache_get(dir, stat.mtime)
    if cached then
        return cached.visible
    end

    local visible = {}
    local names = 0
    local weight = 0
    local tail = ''
    local read_error
    local function read(data)
        if not data then
            return
        end
        local chunk = tail .. data
        local start = 1
        while true do
            local stop = chunk:find('\0', start, true)
            if not stop then
                tail = chunk:sub(start)
                return
            end
            local name = chunk:sub(start, stop - 1):match('^[^/]+')
            if name and not visible[name] then
                visible[name] = true
                names = names + 1
                weight = weight + #name + 64
            end
            start = stop + 1
        end
    end

    local ok, process = pcall(vim.system, {
        'git',
        '-C',
        dir,
        'ls-files',
        '-z',
        '--cached',
        '--others',
        '--exclude-standard',
        '--',
        '.',
    }, {
        stdout = function(err, data)
            read_error = read_error or err
            read(data)
        end,
        stderr = false,
    })
    local result = ok and process:wait() or nil
    if not result or result.code ~= 0 or read_error then
        cache_put(dir, stat.mtime, false, git_failure_ttl)
        return false
    end

    if names <= git_cache_max_names and weight <= git_cache_max_weight then
        cache_put(dir, stat.mtime, visible, git_cache_ttl)
    end
    return visible
end

vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('dir_git_visible', { clear = true }),
    pattern = 'DirReadPost',
    callback = function(args)
        if vim.b[args.buf].dir_git_visible == false then
            return
        end

        local dir = vim.api.nvim_buf_get_name(args.buf)
        local visible = git_visible(dir)
        if not visible then
            vim.b[args.buf].dir_git_visible = false
            return
        end
        vim.b[args.buf].dir_git_visible = true

        local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, true)
        local filtered = vim.tbl_filter(function(line)
            local name = line:sub(-1) == '/' and line:sub(1, -2) or line
            return visible[name:gsub('%z', '\n')] == true
        end, lines)
        vim.api.nvim_buf_set_lines(args.buf, 0, -1, true, filtered)
    end,
})

vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, buf)
        return vim.bo[buf].filetype == 'directory'
    end,
    on_range = function(_, _, buf, row)
        local dir = vim.api.nvim_buf_get_name(buf)
        local name = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
        local path = vim.fs.joinpath(dir, (name:gsub('/$', '')))
        local stat = vim.uv.fs_lstat(path) or {}
        local exe = stat.type == 'file'
            and bit.band(stat.mode, tonumber('111', 8)) ~= 0
        local char = glyph[stat.type] or (exe and '*')
        if char then
            vim.api.nvim_buf_set_extmark(buf, ns, row, #name, {
                virt_text = { { char, 'Dimmed' } },
                virt_text_pos = 'overlay',
                hl_mode = 'combine',
                ephemeral = true,
            })
        end
        if stat.type == 'link' then
            local target = vim.uv.fs_readlink(path) or '?'
            if target:sub(1, 1) == '/' then
                target = vim.fn.fnamemodify(target, ':~')
            end
            vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
                virt_text = { { '-> ' .. target, 'Dimmed' } },
                virt_text_pos = 'eol',
                hl_mode = 'combine',
                ephemeral = true,
            })
        end
        ---@diagnostic disable-next-line: return-type-mismatch
        return row + 1
    end,
})
