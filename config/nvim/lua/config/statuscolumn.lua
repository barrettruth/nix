local M = {}

local review_prefix = 'diffs://review:'
local window_options = {}

local function is_review_buffer(buf)
    return vim.startswith(vim.api.nvim_buf_get_name(buf), review_prefix)
end

local function update_window(win, buf)
    if is_review_buffer(buf) then
        if not window_options[win] then
            window_options[win] = {
                number = vim.api.nvim_get_option_value('number', { win = win }),
                relativenumber = vim.api.nvim_get_option_value(
                    'relativenumber',
                    { win = win }
                ),
            }
        end

        vim.api.nvim_set_option_value('number', false, { win = win })
        vim.api.nvim_set_option_value('relativenumber', false, { win = win })
        return
    end

    local options = window_options[win]
    if not options then
        return
    end

    vim.api.nvim_set_option_value('number', options.number, { win = win })
    vim.api.nvim_set_option_value(
        'relativenumber',
        options.relativenumber,
        { win = win }
    )
    window_options[win] = nil
end

function M.render()
    if vim.v.virtnum ~= 0 then
        return ''
    end

    local column = '%s%C '

    if vim.startswith(vim.api.nvim_buf_get_name(0), review_prefix) then
        return column
    end

    return column .. '%=%{v:relnum?v:relnum:v:lnum} '
end

function M.setup()
    vim.o.statuscolumn = "%{%v:lua.require'config.statuscolumn'.render()%}"

    local aug = vim.api.nvim_create_augroup('StatusColumn', { clear = true })

    vim.api.nvim_create_autocmd(
        { 'BufEnter', 'BufFilePost', 'BufWinEnter', 'WinEnter' },
        {
            callback = function(args)
                update_window(
                    vim.api.nvim_get_current_win(),
                    args.buf or vim.api.nvim_get_current_buf()
                )
            end,
            group = aug,
        }
    )

    vim.api.nvim_create_autocmd('WinClosed', {
        callback = function(args)
            window_options[tonumber(args.match)] = nil
        end,
        group = aug,
    })

    update_window(
        vim.api.nvim_get_current_win(),
        vim.api.nvim_get_current_buf()
    )
end

return M
