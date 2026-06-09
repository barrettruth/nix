local api = vim.api
local fzf_builtin = require('fzf-lua.previewer.builtin')
local fzf_config = require('fzf-lua.config')
local fzf_path = require('fzf-lua.path')
local fzf_utils = require('fzf-lua.utils')

---@class fzf.preview.Entry
---@field argv string[]

---@class fzf.preview.Previewer : fzf-lua.previewer.BufferOrFile,{}
---@field super fzf-lua.previewer.BufferOrFile
---@field _parse fun(self: fzf.preview.Previewer, entry_str: string): fzf.preview.Entry?
---@field _job? vim.SystemObj
---@field _last_entry? string
---@field _file? string
---@field _icons table<string, string>

---@param cmd? string
---@return string?
local function file_from_cmd(cmd)
    if not cmd then
        return nil
    end
    local last = cmd:match('([^%s]+)%s*$')
    if not last then
        return nil
    end
    if last:sub(1, 1) == "'" and last:sub(-1) == "'" then
        last = last:sub(2, -2):gsub([['\'']], "'")
    end
    return last
end

---@return table<string, string>
local function build_icons()
    local overrides = fzf_config.globals.git and fzf_config.globals.git.icons
    local icons = {}
    for _, code in ipairs({ 'D', 'M', 'R', 'A', 'C', 'T', '?' }) do
        icons[code] = overrides
                and overrides[code]
                and fzf_utils.lua_regex_escape(overrides[code].icon)
            or code
    end
    return icons
end

---@param entry_str string
---@return string?
local function first_word(entry_str)
    return fzf_utils.strip_ansi_coloring(entry_str):match('%S+')
end

---@param parse fun(self: fzf.preview.Previewer, entry_str: string): fzf.preview.Entry?
---@return fzf.preview.Previewer
local function make_class(parse)
    ---@type fzf.preview.Previewer
    local P = fzf_builtin.buffer_or_file:extend()

    function P:new(o, opts, fzf_win)
        P.super.new(self, o, opts, fzf_win)
        setmetatable(self, P)
        self._parse = parse
        self._icons = build_icons()
        self._file = file_from_cmd(opts.cmd)
        return self
    end

    ---@param entry_str string
    function P:populate_preview_buf(entry_str)
        if not self.win or not self.win:validate_preview() then
            return
        end
        if self.stop_job then
            self.stop_job()
            self.stop_job = nil
        end

        local entry = self:_parse(entry_str)
        self._last_entry = entry_str
        if not entry then
            self:_render({ 'cannot preview:', entry_str })
            return
        end

        self._job = vim.system(
            entry.argv,
            { text = true, cwd = self.opts.cwd or vim.uv.cwd() },
            vim.schedule_wrap(function(res)
                if entry_str ~= self._last_entry then
                    return
                end
                if not self.win or not self.win:validate_preview() then
                    return
                end
                self:_render(self:_format(res))
            end)
        )
        self.stop_job = function()
            if self._job and not self._job:is_closing() then
                self._job:kill(9)
            end
        end
    end

    ---@param res vim.SystemCompleted
    ---@return string[]
    function P:_format(res)
        if res.code ~= 0 then
            local lines = { ('git exited %d'):format(res.code), '' }
            vim.list_extend(
                lines,
                vim.split(res.stderr or '', '\n', { plain = true })
            )
            return lines
        end
        return vim.split(res.stdout or '', '\n', { plain = true })
    end

    ---@param lines string[]
    function P:_render(lines)
        local buf = self:get_tmp_buffer()
        api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].filetype = 'git'
        self:set_preview_buf(buf)
        if self.win and self.win.update_preview_scrollbar then
            self.win:update_preview_scrollbar()
        end
    end

    return P
end

---@param self fzf.preview.Previewer
---@param entry_str string
---@return fzf.preview.Entry?
local function parse_status(self, entry_str)
    local icons = self._icons
    local nbsp = fzf_utils.nbsp

    local is_untracked = entry_str:match(
        '[' .. icons['?'] .. icons.C .. ']' .. nbsp
    ) ~= nil

    local s = entry_str
    if s:match('%s%->%s') then
        s = s:match('%s%->%s(.*)$') or s
    end
    local entry = fzf_path.entry_to_file(s, self.opts)
    if not entry.path then
        return nil
    end

    if is_untracked then
        local stat = vim.uv.fs_stat(entry.path)
        if stat and stat.type == 'directory' then
            return { argv = { 'ls', '-la', entry.path } }
        end
        return {
            argv = {
                'git',
                'diff',
                '--no-color',
                '--no-index',
                '/dev/null',
                entry.path,
            },
        }
    end

    return {
        argv = { 'git', 'diff', '--no-color', 'HEAD', '--', entry.path },
    }
end

---@param _ fzf.preview.Previewer
---@param entry_str string
---@return fzf.preview.Entry?
local function parse_commits(_, entry_str)
    local sha = first_word(entry_str)
    if not sha then
        return nil
    end
    return { argv = { 'git', 'show', '--no-color', sha } }
end

---@param self fzf.preview.Previewer
---@param entry_str string
---@return fzf.preview.Entry?
local function parse_bcommits(self, entry_str)
    local sha = first_word(entry_str)
    if not sha or not self._file then
        return nil
    end
    return {
        argv = { 'git', 'show', '--no-color', sha, '--', self._file },
    }
end

---@param self fzf.preview.Previewer
---@param entry_str string
---@return fzf.preview.Entry?
local function parse_diff(self, entry_str)
    local entry = fzf_path.entry_to_file(entry_str, self.opts)
    if not entry.path then
        return nil
    end
    local argv = { 'git', 'diff', '--no-color' }
    if self.opts.ref1 then
        table.insert(argv, self.opts.ref1)
    end
    local ref = self.opts.ref
    if type(ref) == 'table' then
        for _, r in ipairs(ref) do
            table.insert(argv, r)
        end
    elseif type(ref) == 'string' then
        table.insert(argv, ref)
    end
    table.insert(argv, '--')
    table.insert(argv, entry.path)
    return { argv = argv }
end

---@param _ fzf.preview.Previewer
---@param entry_str string
---@return fzf.preview.Entry?
local function parse_stash(_, entry_str)
    local ref = fzf_utils.strip_ansi_coloring(entry_str):match('(stash@{%d+})')
    if not ref then
        return nil
    end
    return {
        argv = { 'git', 'stash', 'show', '--patch', '--no-color', ref },
    }
end

local M = {}

M.status = {
    _ctor = function()
        return make_class(parse_status)
    end,
}
M.commits = {
    _ctor = function()
        return make_class(parse_commits)
    end,
}
M.bcommits = {
    _ctor = function()
        return make_class(parse_bcommits)
    end,
}
M.diff = {
    _ctor = function()
        return make_class(parse_diff)
    end,
}
M.stash = {
    _ctor = function()
        return make_class(parse_stash)
    end,
}

return M
