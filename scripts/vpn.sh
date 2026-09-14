#!/usr/bin/env bash
set -euo pipefail

ivpn=@ivpn@
tailscale=@tailscale@

usage() {
  printf '%s\n' \
    'Usage: vpn setup | connect [LOCATION] | disconnect | status' \
    'Log in through the IVPN app or interactive ivpn login before connecting.' \
    'connect blocks ordinary internet until connected; disconnect releases that block.'
}

configure() {
  local exceptions=""
  if @tailnet@; then
    exceptions=$("$tailscale" status --json | jq -er '
      if .BackendState != "Running" then error("Start Tailscale before configuring the VPN")
      else [.Self.TailscaleIPs[]?, .Peer[]?.TailscaleIPs[]?, "100.100.100.100"]
        | unique | join(",")
      end
    ')
  fi
  "$ivpn" autoconnect -on_launch off
  "$ivpn" firewall -persistent_off -lan_block -exceptions "$exceptions"
  "$ivpn" antitracker -off
  "$ivpn" dns -doh 'https://dns.quad9.net/dns-query' 9.9.9.9
  "$ivpn" logs -off
}

command=${1:-status}
if [ "$#" -gt 0 ]; then shift; fi
case "$command" in
-h | --help | help)
  usage
  exit 0
  ;;
setup | disconnect | status)
  if [ "$#" -ne 0 ]; then
    usage >&2
    exit 2
  fi
  ;;
connect)
  if [ "$#" -gt 1 ] || [[ ${1:-} == -* ]]; then
    usage >&2
    exit 2
  fi
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

if [ ! -x "$ivpn" ]; then
  printf '%s\n' 'Install and open the official IVPN app before using vpn.' >&2
  exit 1
fi

case "$command" in
setup)
  configure
  ;;
connect)
  configure
  "$ivpn" firewall -on
  exec "$ivpn" connect -protocol WireGuard -fastest "$@"
  ;;
disconnect)
  "$ivpn" disconnect
  exec "$ivpn" firewall -off
  ;;
status)
  exec "$ivpn" status
  ;;
esac
