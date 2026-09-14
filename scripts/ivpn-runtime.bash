ivpn_bypass_duration() {
  printf '%s\n' 300
}

ivpn_bypass_active() {
  local file=$1 dir issued expires extra now duration
  [ -n "$file" ] && [ -f "$file" ] && [ ! -L "$file" ] || return 1
  dir=${file%/*}
  [ ! -L "$dir" ] && [ "$(/usr/bin/stat -f '%u:%Lp' "$dir")" = "0:700" ] || return 1
  [ "$(/usr/bin/stat -f '%u:%Lp' "$file")" = "0:600" ] || return 1
  read -r issued expires extra <"$file" || return 1
  [[ "$issued" =~ ^[1-9][0-9]{9,11}$ && "$expires" =~ ^[1-9][0-9]{9,11}$ && -z "$extra" ]] || return 1
  now=$(date +%s)
  duration=$(ivpn_bypass_duration)
  ((expires - issued == duration && issued <= now && now < expires))
}
