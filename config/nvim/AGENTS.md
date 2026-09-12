# nvim

- Never write a comment. Not to explain a Vim or Neovim gotcha, not to justify
  why the obvious alternative fails, not to name another project as the source.
  The existing ones are the author's and are not a licence to add more.
- LuaCATS annotations are not comments; use them exactly as the file already
  does, and leave a file that has none without any.
- Establish authorship with `git blame` before proposing that a comment be
  rewritten; the deliberate ones read like accidents.
- Directory-browser actions are primitive mappings to existing Ex or shell
  commands, not custom file-operation commands.
- A mux view is a tab, not a terminal singleton. Multiple zsh buffers must work
  in any view. Editor and review helpers preserve other splits. Session restore
  recreates terminal panes and commands, not running process state.
- Direnv progress belongs to the mux server, not the shell that started the load.
