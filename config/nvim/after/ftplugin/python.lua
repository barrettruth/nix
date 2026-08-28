if vim.bo.buftype ~= '' or vim.fn.expand('%:t:r') == '' then
    return
end

vim.bo.errorformat = table.concat({
    [[%A  File "%f"\, line %l%.%#]],
    [[%C %.%#]],
    [[%Z%[%^ ]%\@=%m]],
}, ',')
vim.b.run = 'python3 %:S'
