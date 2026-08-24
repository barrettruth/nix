# nvim

- Comment in the style the file already uses (if none/very few - match that), LuaCATS and analogous doc-comment
  systems included: a file with no comments (excluding builtin docstring
  comments) takes none.
- A comment carries the why in a sentence — a constraint the API imposes, a Vim
  or Neovim gotcha, why the obvious alternative fails — and names the source
  when the reason is another project's. It never restates the code, re-argues a
  settled decision, or records the moment rather than the design.
- Establish authorship with `git blame` before proposing that a comment be
  rewritten; the deliberate ones read like accidents.
