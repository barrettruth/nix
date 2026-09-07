vim.opt_local.number = true
vim.opt_local.relativenumber = true
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
    .. '\nsetl et< ts< sts< sw< wrap< bri< lbr< cc< list< isk< nu< rnu< fdc< scl< tfu< fen< fdm< fdn<|sil! nunmap <buffer> j|sil! nunmap <buffer> k|sil! nunmap <buffer> gO|sil! nunmap <buffer> <2-LeftMouse>|sil! nunmap <buffer> q'
