#!/usr/bin/env bash
set -euo pipefail

ivpn=@ivpn@
state_dir=@state_dir@
exceptions=@exceptions@

if [ ! -x "$ivpn" ] || [ ! -s "$state_dir/port.txt" ] || [ ! -s "$state_dir/settings.json" ]; then
  exit 0
fi

current=$(jq -ce '
  if ([.IsFwPersistant, .IsFwAllowLAN, .IsLogging,
       .IsAutoconnectOnLaunch, .IsAutoconnectOnLaunchDaemon] | all(type == "boolean"))
     and (.LastConnectionParams | type) == "object"
  then {
    persistent: .IsFwPersistant,
    lan: .IsFwAllowLAN,
    exceptions: ((.FwUserExceptions // "") | gsub("\\s"; "")),
    dns: .LastConnectionParams.ManualDNS,
    antitracker: (.LastConnectionParams.Metadata.AntiTracker.Enabled // false),
    logging: .IsLogging,
    launch: .IsAutoconnectOnLaunch,
    background: .IsAutoconnectOnLaunchDaemon
  }
  else error("Unsupported IVPN settings schema")
  end
' "$state_dir/settings.json")

matches() {
  jq -e "$@" <<<"$current" >/dev/null
}

has_profile() {
  jq -e '.LastConnectionParams |
    if .VpnType == 1 then (.WireGuardParameters.EntryVpnServer.Hosts | length) > 0
    elif .VpnType == 0 then (.OpenVpnParameters.EntryVpnServer.Hosts | length) > 0
    else false end
  ' "$state_dir/settings.json" >/dev/null
}

if ! matches --arg exceptions "$exceptions" ".persistent == false and .lan == false and .exceptions == \$exceptions"; then
  "$ivpn" firewall -persistent_off -lan_block -exceptions "$exceptions" >/dev/null
fi

if ! matches '.antitracker == false and (.dns.Servers | length) == 1
    and .dns.Servers[0].Address == "9.9.9.9"
    and .dns.Servers[0].Encryption == 2
    and .dns.Servers[0].Template == "https://dns.quad9.net/dns-query"'; then
  "$ivpn" dns -doh 'https://dns.quad9.net/dns-query' 9.9.9.9 >/dev/null
fi

if matches '.logging'; then
  "$ivpn" logs -off
fi

if @auto_connect@; then
  if matches '.launch and .background'; then
    exit 0
  fi
  status=$("$ivpn" status 2>/dev/null) || exit 0
  if has_profile; then
    "$ivpn" autoconnect -on_launch on >/dev/null
    if [[ "$status" =~ ^VPN[[:space:]]*:[[:space:]]*DISCONNECTED ]]; then
      "$ivpn" connect -last >/dev/null
    fi
  else
    result=0
    "$ivpn" connect -protocol WireGuard -fastest >/dev/null || result=$?
    if has_profile; then
      "$ivpn" autoconnect -on_launch on >/dev/null
    fi
    exit "$result"
  fi
elif matches '.launch or .background'; then
  "$ivpn" autoconnect -on_launch off >/dev/null
fi
