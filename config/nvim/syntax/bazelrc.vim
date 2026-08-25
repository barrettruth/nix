" Vim syntax file
" Language:  Bazel rc file
" Reference: bazelbuild/bazel src/main/cpp/rc_file.cc, src/main/cpp/util/strings.cc

if exists('b:current_syntax')
  finish
endif

syn iskeyword @,48-57,_,-

syn region bazelrcComment start='#' skip='\\$' end='$' contains=bazelrcTodo,@Spell
syn keyword bazelrcTodo contained TODO FIXME XXX NOTE

syn match bazelrcContinuation '\\$'

" Not contained: an escape has to out-rank the comment, since '\#' is a literal
" '#' rather than the start of a comment.
syn match bazelrcEscape '\\.'
" A missing end-quote is silently ignored rather than spilling into the rest of
" the file, which is as close to Tokenize()'s behaviour as one line can get.
syn region bazelrcString oneline start=+'+ skip=+\\.+ end=+'+ contains=bazelrcEscape
syn region bazelrcString oneline start=+"+ skip=+\\.+ end=+"+ contains=bazelrcEscape

syn match bazelrcImport '^\s*try-import-if-bazel-version\>'
      \ nextgroup=bazelrcVersion skipwhite
syn match bazelrcImport '^\s*\%(try-\)\=import\>' nextgroup=bazelrcPath skipwhite
syn match bazelrcVersion '\%(<=\|>=\|==\|!=\|[<>~]\)[^ \t#]\+'
      \ contained nextgroup=bazelrcPath skipwhite
syn match bazelrcPath '\%(\\.\|[^ \t#]\)\+' contained
      \ contains=bazelrcEscape,bazelrcString,bazelrcWorkspace
syn match bazelrcWorkspace '\%(^\|\s\)\@<=%workspace%/' contained

syn match bazelrcCommand '^\s*\<\%(always\|aquery\|build\|canonicalize-flags\|clean
      \\|common\|config\|coverage\|cquery\|dump\|fetch\|help\|info\|license
      \\|mobile-install\|mod\|print_action\|query\|run\|shutdown\|startup\|test
      \\|vendor\|version\)\>' nextgroup=bazelrcConfig
syn match bazelrcConfig ':[^ \t#]\+' contained

syn match bazelrcFlag '--[^ \t#=]*' nextgroup=bazelrcValue
syn match bazelrcFlag '\%(^\|\s\)\@<=-[a-zA-Z]\>' nextgroup=bazelrcValue
syn region bazelrcValue matchgroup=bazelrcOperator start='=' end='\ze[ \t#]' end='$'
      \ oneline contained contains=bazelrcString,bazelrcEscape

hi def link bazelrcComment Comment
hi def link bazelrcTodo Todo
hi def link bazelrcContinuation Special
hi def link bazelrcEscape SpecialChar
hi def link bazelrcString String
hi def link bazelrcImport Include
hi def link bazelrcVersion Constant
hi def link bazelrcPath String
hi def link bazelrcWorkspace PreProc
hi def link bazelrcCommand Statement
hi def link bazelrcConfig Type
hi def link bazelrcFlag Identifier
hi def link bazelrcOperator Operator

let b:current_syntax = 'bazelrc'
