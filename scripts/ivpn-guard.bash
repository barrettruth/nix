#!/usr/bin/env bash
set -euo pipefail

ivpn=@ivpn@
firewall_script=/Applications/IVPN.app/Contents/Resources/etc/firewall.sh

block_without_daemon() {
  timeout --kill-after=2 15 "$firewall_script" -enable >/dev/null
}

helper=$(/bin/launchctl print system/net.ivpn.client.Helper 2>/dev/null) || {
  block_without_daemon
  printf '%s\n' 'IVPN protection requires attention: open IVPN and approve its privileged helper.' >&2
  exit 1
}
if [[ ! "$helper" =~ state[[:space:]]*=[[:space:]]*running ]]; then
  block_without_daemon
  /bin/launchctl kickstart system/net.ivpn.client.Helper
fi

firewall=$(timeout --kill-after=2 10 "$ivpn" firewall -status) || {
  block_without_daemon
  printf '%s\n' 'IVPN is not responding; its firewall was enabled directly.' >&2
  exit 1
}
if [[ ! "$firewall" =~ Firewall[[:space:]]*:[[:space:]]*Enabled ]]; then
  timeout --kill-after=2 10 "$ivpn" firewall -on >/dev/null || {
    block_without_daemon
    exit 1
  }
fi

policy=$(/bin/launchctl print system/org.nixos.ivpn-policy)
if [[ ! "$policy" =~ state[[:space:]]*=[[:space:]]*running ]]; then
  if ! /bin/launchctl kickstart system/org.nixos.ivpn-policy; then
    policy=$(/bin/launchctl print system/org.nixos.ivpn-policy)
    [[ "$policy" =~ state[[:space:]]*=[[:space:]]*running ]]
  fi
fi
