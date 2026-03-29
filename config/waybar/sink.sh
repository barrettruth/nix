#!/bin/sh
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
pct=$(printf '%s' "$vol" | awk '{printf "%d", $2 * 100}')
name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node\.description/{print $2; exit}')
if printf '%s' "$vol" | grep -q MUTED; then
  icon="󰖁"
elif [ "$pct" -le 33 ]; then
  icon="󰕿"
elif [ "$pct" -le 66 ]; then
  icon="󰖀"
else
  icon="󰕾"
fi
printf '{"text":"%s","tooltip":"Sink: %s\\nVolume: %d%%"}\n' "$icon" "$name" "$pct"
