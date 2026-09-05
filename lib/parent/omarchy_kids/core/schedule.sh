day_key() {
  case $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') in
    mon|monday) echo mon ;;
    tue|tues|tuesday) echo tue ;;
    wed|wednesday) echo wed ;;
    thu|thur|thurs|thursday) echo thu ;;
    fri|friday) echo fri ;;
    sat|saturday) echo sat ;;
    sun|sunday) echo sun ;;
    *) return 1 ;;
  esac
}

# "mon-fri", "mon,wed,fri", "weekdays", "weekends", "daily" -> a JSON array of day keys.
days_json() {
  local spec part first last d days="" week=(mon tue wed thu fri sat sun) i j
  spec=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case $spec in
    weekdays) echo '["mon","tue","wed","thu","fri"]'; return 0 ;;
    weekends) echo '["sat","sun"]'; return 0 ;;
    daily|everyday|all) echo '["mon","tue","wed","thu","fri","sat","sun"]'; return 0 ;;
  esac
  local -a parts
  IFS=, read -ra parts <<<"$spec"
  for part in ${parts[@]+"${parts[@]}"}; do
    if [[ $part == *-* ]]; then
      first=$(day_key "${part%-*}") || return 1
      last=$(day_key "${part#*-}") || return 1
      for i in "${!week[@]}"; do [[ ${week[$i]} == "$first" ]] && break; done
      for j in "${!week[@]}"; do [[ ${week[$j]} == "$last" ]] && break; done
      d=$i
      while :; do
        days+=" ${week[$d]}"
        (( d == j )) && break
        d=$(( (d + 1) % 7 ))
      done
    else
      d=$(day_key "$part") || return 1
      days+=" $d"
    fi
  done
  [[ -n $days ]] || return 1
  printf '%s\n' $days | jq -R . | jq -sc 'unique_by(.) | map(select(. != ""))' | jq -c --argjson week '["mon","tue","wed","thu","fri","sat","sun"]' '[$week[] as $d | select(index($d)) | $d]'
}

# "8:00-15:30" -> "08:00" "15:30"
window_parts() {
  [[ $1 =~ ^([0-9]{1,2}):([0-9]{2})-([0-9]{1,2}):([0-9]{2})$ ]] || return 1
  local sh=$((10#${BASH_REMATCH[1]})) sm=$((10#${BASH_REMATCH[2]})) eh=$((10#${BASH_REMATCH[3]})) em=$((10#${BASH_REMATCH[4]}))
  (( sh < 24 && sm < 60 && eh < 24 && em < 60 )) || return 1
  printf '%02d:%02d %02d:%02d' "$sh" "$sm" "$eh" "$em"
}

# Replace the periods with a label and mode by new ones, keeping the rest.
