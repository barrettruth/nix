#!/bin/sh
set -eu

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'cp: required clipboard command not found: %s\n' "$1" >&2
    exit 127
  fi
}

case "$(uname -s)" in
Darwin)
  require pbcopy
  exec pbcopy
  ;;
Linux)
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    require wl-copy
    exec wl-copy
  fi

  require xclip
  exec xclip -selection clipboard
  ;;
*)
  printf 'cp: unsupported operating system: %s\n' "$(uname -s)" >&2
  exit 1
  ;;
esac
