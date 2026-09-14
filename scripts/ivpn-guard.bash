#!/usr/bin/env bash
set -euo pipefail

ivpn=@ivpn@
policy=@policy@

helper=$(/bin/launchctl print system/net.ivpn.client.Helper 2>/dev/null) || {
  printf '%s\n' 'IVPN protection unavailable: open IVPN and approve its privileged helper.' >&2
  exit 1
}
if [[ ! "$helper" =~ state[[:space:]]*=[[:space:]]*running ]]; then
  /bin/launchctl kickstart system/net.ivpn.client.Helper
fi

firewall=$(timeout --kill-after=2 10 "$ivpn" firewall -status)
if [[ ! "$firewall" =~ Firewall[[:space:]]*:[[:space:]]*Enabled ]]; then
  timeout --kill-after=2 10 "$ivpn" firewall -on >/dev/null
fi

timeout --kill-after=2 30 "$policy"
