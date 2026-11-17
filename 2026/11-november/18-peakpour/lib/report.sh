# shellcheck shell=bash
# Peakpour's report: the month-by-month plan, anything that will pass its best, and the pace needed.

# "Barossa Shiraz 2016 x2, Hunter Semillon 2019" from a list of wine numbers.
pp_names() {
  local -A seen=()
  local -a order=()
  local w out=''
  for w in "$@"; do
    [[ -n ${seen[$w]:-} ]] || order+=("$w")
    seen[$w]=$((${seen[$w]:-0} + 1))
  done
  for w in "${order[@]}"; do
    [[ -n $out ]] && out+=', '
    out+=${PP_NAME[w]}
    ((seen[$w] > 1)) && out+=" x${seen[$w]}"
  done
  printf '%s' "$out"
}

pp_report() {
  local rate=$1 total=0 w missed=0 past=0 line t months=0
  for w in "${!PP_NAME[@]}"; do
    total=$((total + PP_COUNT[w])) missed=$((missed + PP_MISSED[w])) past=$((past + PP_PAST[w]))
  done
  printf 'Peakpour: %d bottles of %d wines, %d a month from %s\n\n' "$total" "${#PP_NAME[@]}" "$rate" "$(pp_fmt "$PP_START")"
  for line in "${PP_PLAN[@]}"; do
    read -r t rest <<<"$line"
    # shellcheck disable=SC2086 # wine numbers, split on purpose
    printf '  %-9s %s\n' "$(pp_fmt "$t")" "$(pp_names $rest)"
    months=$((months + 1))
  done
  ((months)) || printf '  (nothing to open)\n'
  printf '\n'
  if ((missed == 0 && past == 0)); then
    printf 'Every bottle is opened inside its drinking window.\n'
  else
    if ((past > 0)); then
      printf 'Already past their best at the start (open these first, or cook with them):\n'
      for w in "${!PP_NAME[@]}"; do
        ((PP_PAST[w] > 0)) && printf '  %s: %d bottle%s, window closed %s\n' "${PP_NAME[w]}" "${PP_PAST[w]}" "$( ((PP_PAST[w] > 1)) && echo s)" "$(pp_fmt "${PP_UNTIL[w]}")"
      done
    fi
    if ((missed > 0)); then
      printf 'At %d a month, %d bottle%s will pass %s best:\n' "$rate" "$missed" "$( ((missed > 1)) && echo s)" "$( ((missed > 1)) && echo their || echo its)"
      for w in "${!PP_NAME[@]}"; do
        ((PP_MISSED[w] > 0)) && printf '  %s: %d of %d, window closes %s\n' "${PP_NAME[w]}" "${PP_MISSED[w]}" "${PP_COUNT[w]}" "$(pp_fmt "${PP_UNTIL[w]}")"
      done
    fi
  fi
  if ((PP_NEED > 0)); then
    local span=$((PP_CRUNCH_TO - PP_CRUNCH_FROM + 1))
    printf '\nTo open every bottle in time you need %d a month. The tightest stretch is %s to %s:\n' "$PP_NEED" "$(pp_fmt "$PP_CRUNCH_FROM")" "$(pp_fmt "$PP_CRUNCH_TO")"
    if ((span == 1)); then
      printf '  %d bottles must be drunk in that one month.\n' "$PP_CRUNCH_BOTTLES"
    else
      printf '  %d bottles must be drunk in those %d months.\n' "$PP_CRUNCH_BOTTLES" "$span"
    fi
    ((rate > PP_NEED)) && printf '  At %d a month you have room to buy more, or to drink slower.\n' "$rate"
  fi
  return 0
}
