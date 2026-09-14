#!/usr/bin/env bash
set -euo pipefail

ivpn=@ivpn@
problem=""
for name in ivpn-guard ivpn-policy; do
  if ! state=$(/bin/launchctl print "system/org.nixos.$name" 2>/dev/null); then
    problem="The IVPN protection service is not loaded. Open IVPN and review its permissions."
    break
  fi
  if [[ ! "$state" =~ state[[:space:]]*=[[:space:]]*running ]] &&
    [[ "$state" =~ last\ exit\ code[[:space:]]*=[[:space:]]*[1-9][0-9]* ]]; then
    problem="IVPN protection needs attention. Open IVPN; details are in /var/log/$name.log."
    break
  fi
done

if [ -z "$problem" ]; then
  if ! status=$(timeout --kill-after=2 10 "$ivpn" status 2>/dev/null); then
    problem="Open IVPN to sign in or restore access to its helper."
  elif [[ "$status" == *"Unhealthy Connection"* ]]; then
    problem="IVPN reports an unhealthy tunnel. Open the app to reconnect."
  fi
fi
[ -n "$problem" ] || exit 0

/usr/bin/osascript - "$problem" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title "IVPN needs attention"
end run
APPLESCRIPT
