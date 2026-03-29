#!/bin/sh
vol=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
pct=$(printf '%s' "$vol" | awk '{printf "%d", $2 * 100}')
name=$(wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk -F'"' '/node\.description/{print $2; exit}')
if printf '%s' "$vol" | grep -q MUTED; then
  icon="󰍭"
else
  icon="󰍬"
fi
printf '{"text":"%s","tooltip":"Source: %s\\nVolume: %d%%"}\n' "$icon" "$name" "$pct"
