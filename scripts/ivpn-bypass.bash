#!/usr/bin/env bash
set -euo pipefail

ivpn=@ivpn@
bypass_file=@bypass_file@
firewall_script=/Applications/IVPN.app/Contents/Resources/etc/firewall.sh

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'A temporary IVPN bypass requires administrator approval.' >&2
  exit 1
fi
if [ "$bypass_file" != "/var/run/ivpn/bypass" ]; then
  printf '%s\n' 'Temporary bypass is not configured for this host.' >&2
  exit 1
fi
if ivpn_bypass_active "$bypass_file"; then
  printf '%s\n' 'The existing five-minute bypass is still active; it was not extended.'
  exit 0
fi

dir=$(dirname -- "$bypass_file")
if [ -L "$dir" ] || [ -L "$bypass_file" ]; then
  printf '%s\n' 'Refusing an unsafe IVPN bypass path.' >&2
  exit 1
fi
install -d -m 0700 -o root -g wheel "$dir"
tmp=$(mktemp "$dir/.bypass.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
issued=$(date +%s)
duration=$(ivpn_bypass_duration)
printf '%s %s\n' "$issued" "$((issued + duration))" >"$tmp"
chmod 0600 "$tmp"
mv -f -- "$tmp" "$bypass_file"

restore_on_error() {
  rm -f -- "$bypass_file"
  timeout --kill-after=2 15 "$firewall_script" -enable >/dev/null || true
  /bin/launchctl kickstart system/org.nixos.ivpn-guard >/dev/null 2>&1 || true
}
trap restore_on_error ERR
/bin/launchctl kill SIGTERM system/org.nixos.ivpn-policy >/dev/null 2>&1 || true

if timeout --kill-after=2 10 "$ivpn" firewall -status >/dev/null 2>&1; then
  timeout --kill-after=2 10 "$ivpn" autoconnect -on_launch off >/dev/null
  timeout --kill-after=2 10 "$ivpn" firewall -persistent_off >/dev/null
  status=$(timeout --kill-after=2 10 "$ivpn" status 2>/dev/null) || true
  if [[ ! "$status" =~ VPN[[:space:]]*:[[:space:]]*DISCONNECTED ]]; then
    timeout --kill-after=2 10 "$ivpn" disconnect >/dev/null
  fi
  timeout --kill-after=2 10 "$ivpn" firewall -off >/dev/null
else
  timeout --kill-after=2 15 "$firewall_script" -disable >/dev/null
fi
trap - ERR
printf '%s\n' 'Unprotected network access allowed for five minutes; the guard restores protection afterward.'
