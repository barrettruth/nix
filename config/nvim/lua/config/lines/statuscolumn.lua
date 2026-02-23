return {
    -- overlay relative numbers and line numbers directly on top of eachother
    num = function()
        if math.abs(vim.v.virtnum) > 0 then
            return ''
        end

        local lnum = vim.v.lnum
        local relnum = vim.v.relnum
        local hl = relnum == 0 and 'CursorLineNr' or 'LineNr'

        local marks = vim.api.nvim_buf_get_extmarks(
            0,
            -1,
            { lnum - 1, 0 },
            { lnum - 1, 0 },
            { details = true }
        )
        for _, mark in ipairs(marks) do
            if mark[4] and mark[4].number_hl_group then
                hl = mark[4].number_hl_group
                break
            end
        end

        return '%#' .. hl .. '#' .. (relnum == 0 and lnum or relnum)
    end,
    fold = function()
        local expr = require('config.fold').foldexpr()
        if expr:sub(1, 1) == '>' then
            if vim.fn.foldclosed(vim.v.lnum) ~= -1 then
                return '>'
            else
                return 'v'
            end
        end
        return ' '
    end,
    sign = function()
        local marks = vim.api.nvim_buf_get_extmarks(
            0, -1, { vim.v.lnum - 1, 0 }, { vim.v.lnum - 1, -1 },
            { details = true, type = 'sign' }
        )
        for _, mark in ipairs(marks) do
            local d = mark[4]
            if d and d.sign_text then
                local text = vim.trim(d.sign_text)
                if text ~= '' then
                    return '%#' .. (d.sign_hl_group or 'SignColumn') .. '#' .. text
                end
            end
        end
        return ' '
    end,
    statuscolumn = function()
        return '%{%v:lua.require("config.lines.statuscolumn").sign()%}%{%v:lua.require("config.lines.statuscolumn").fold()%}%=%{%v:lua.require("config.lines.statuscolumn").num()%} '
    end,
}
