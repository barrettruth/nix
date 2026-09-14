readonly ivpn_bypass_seconds=300

ivpn_bypass_active() {
  local file=$1 issued expires extra now
  [ -n "$file" ] && [ -f "$file" ] && [ ! -L "$file" ] || return 1
  [ "$(/usr/bin/stat -f '%u:%Lp' "$file")" = "0:600" ] || return 1
  read -r issued expires extra <"$file" || return 1
  [[ "$issued" =~ ^[1-9][0-9]{9,11}$ && "$expires" =~ ^[1-9][0-9]{9,11}$ && -z "$extra" ]] || return 1
  now=$(date +%s)
  (( expires - issued == ivpn_bypass_seconds && issued <= now && now < expires ))
}
