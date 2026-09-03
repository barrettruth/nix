if vim.bo.buftype ~= '' or vim.fn.expand('%:t:r') == '' then
    return
end

vim.bo.errorformat = table.concat({
    [[%A  File "%f"\, line %l%.%#]],
    [[%C %.%#]],
    [[%Z%[%^ ]%\@=%m]],
    [[%-G%.%#]],
}, ',')
local run = type(vim.b.run) == 'table' and vim.b.run or {}
run.command = 'python3 %:S'
vim.b.run = run
