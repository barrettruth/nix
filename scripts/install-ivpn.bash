#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  printf '%s\n' 'Usage: install-ivpn DMG APPLICATION' >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'IVPN installation must run through privileged Nix activation.' >&2
  exit 1
fi

image=$1
app=$2
if [ -L "$app" ] || { [ -e "$app" ] && [ ! -d "$app" ]; }; then
  printf 'Refusing to replace a symlink or non-directory: %s\n' "$app" >&2
  exit 1
fi

parent=$(dirname -- "$app")
work=$(mktemp -d "$parent/.ivpn-install.XXXXXX")
backup=""
cleanup() {
  local status=$?
  if [ -n "$backup" ] && [ -d "$backup/IVPN.app" ] && [ ! -e "$app" ] && [ ! -L "$app" ]; then
    mv -T -- "$backup/IVPN.app" "$app" || status=1
  fi
  if [ -d "$work/mount" ] && [ "$(/usr/bin/stat -f %d "$work/mount")" != "$(/usr/bin/stat -f %d "$work")" ]; then
    /usr/bin/hdiutil detach "$work/mount" >/dev/null || return 1
  fi
  rm -rf -- "$work"
  if [ -n "$backup" ] && [ ! -e "$backup/IVPN.app" ]; then
    rmdir -- "$backup"
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$work/mount"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$work/mount" "$image" >/dev/null
if [ ! -d "$work/mount/IVPN.app" ] || [ -L "$work/mount/IVPN.app" ]; then
  printf '%s\n' 'IVPN disk image does not contain an app bundle.' >&2
  exit 1
fi
candidate="$work/IVPN.app"
/usr/bin/ditto --rsrc --extattr --acl "$work/mount/IVPN.app" "$candidate"
/usr/bin/hdiutil detach "$work/mount" >/dev/null
chown -R --no-dereference root:wheel "$candidate"
/usr/bin/codesign --verify --deep --strict "$candidate"

cdhash() {
  /usr/bin/codesign --display --verbose=4 "$1" 2>&1 | awk -F= '/^CDHash=/ { print $2 }'
}
expected=$(cdhash "$candidate")
if [ -z "$expected" ]; then
  printf '%s\n' 'Unable to identify the signed IVPN build.' >&2
  exit 1
fi

if [ -d "$app" ]; then
  installed=$(cdhash "$app")
  if [ "$installed" = "$expected" ] && /usr/bin/codesign --verify --deep --strict "$app"; then
    exit 0
  fi
  if /usr/bin/pgrep -f '/IVPN[.]app/Contents/' >/dev/null || /usr/bin/pgrep -x 'IVPN Agent' >/dev/null; then
    printf '%s\n' 'IVPN or its background agent is running; refusing to replace the app.' >&2
    exit 1
  fi
  backup=$(mktemp -d "$parent/.ivpn-backup.XXXXXX")
  mv -T -- "$app" "$backup/IVPN.app"
  printf 'Previous IVPN app retained at %s/IVPN.app\n' "$backup"
fi

mv -T --no-clobber -- "$candidate" "$app"
if [ -e "$candidate" ]; then
  printf 'Another application appeared at %s; refusing to overwrite it.\n' "$app" >&2
  exit 1
fi
printf 'Installed IVPN at %s\n' "$app"
