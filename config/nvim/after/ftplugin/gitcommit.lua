require('config.completion.gitcommit').setup()

-- mux: when this buffer is opened via `nvim --remote-wait` from a :terminal,
-- wipe it on close so `:wq` unblocks the waiting git (buffers are 'hidden' by
-- default, which would otherwise leave --remote-wait hanging).
vim.bo.bufhidden = 'wipe'
