# shellcheck shell=bash
# The results are globals read by lib/report.sh and the tests, so 'unused' warnings don't apply.
# shellcheck disable=SC2034
# Peakpour's library: reading a cellar list and planning which bottles to open each month so each
# one is drunk inside its drinking window. Sourced by bin/peakpour and by the tests.
#
# Months are whole numbers: year * 12 + (month - 1). A window "2026-03 to 2030" runs from March
# 2026 to December 2030 inclusive.

readonly PP_MAX_BYTES=65536 PP_MAX_LINE=200 PP_MAX_WINES=200 PP_MAX_BOTTLES=2000 PP_MAX_RATE=100
readonly PP_MAX_SPAN=600  # months from the start to the last window's end (50 years)

pp_die() { printf 'peakpour: %s\n' "$1" >&2; exit 2; }

# "2026" (as a start: January; as an end: December) or "2026-03" to a month number.
pp_month() {
  local s=$1 end=$2
  if [[ $s =~ ^(19[5-9][0-9]|2[01][0-9][0-9])$ ]]; then
    printf '%d' $((10#$s * 12 + (end ? 11 : 0)))
  elif [[ $s =~ ^(19[5-9][0-9]|2[01][0-9][0-9])-(0[1-9]|1[0-2])$ ]]; then
    printf '%d' $((10#${BASH_REMATCH[1]} * 12 + 10#${BASH_REMATCH[2]} - 1))
  else
    return 1
  fi
}

# A month number to "Nov 2026".
pp_fmt() {
  local -a names=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  printf '%s %d' "${names[$1 % 12]}" $(($1 / 12))
}

trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# Reads the cellar text into globals: PP_START, PP_RATE (empty if not given), and per wine
# PP_NAME PP_COUNT PP_FROM PP_UNTIL. Errors give the line number, never the line itself.
pp_parse() {
  local text=$1 line n=0 total=0 f
  local re_name="^[[:alnum:]][[:alnum:] '().&/-]{0,59}$"
  PP_START='' PP_RATE='' PP_NAME=() PP_COUNT=() PP_FROM=() PP_UNTIL=()
  ((${#text} <= PP_MAX_BYTES)) || pp_die 'the cellar list is larger than 64 KB'
  if LC_ALL=C grep -q $'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' <<<"$text"; then
    pp_die 'the cellar list has a control character'
  fi
  iconv -f UTF-8 -t UTF-8 <<<"$text" >/dev/null 2>&1 || pp_die 'the cellar list is not valid UTF-8 text'
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    ((${#line} <= PP_MAX_LINE)) || pp_die "line $n: is longer than $PP_MAX_LINE characters"
    line=$(trim "${line%%#*}")
    [[ -n $line ]] || continue
    if [[ $line =~ ^start[[:space:]]+([0-9-]+)$ ]]; then
      PP_START=$(pp_month "${BASH_REMATCH[1]}" 0) || pp_die "line $n: start is a month like 2026-11"
      continue
    fi
    if [[ $line =~ ^rate[[:space:]]+([0-9]{1,3})$ ]]; then
      PP_RATE=$((10#${BASH_REMATCH[1]}))
      ((PP_RATE >= 1 && PP_RATE <= PP_MAX_RATE)) || pp_die "line $n: rate is 1 to $PP_MAX_RATE bottles a month"
      continue
    fi
    IFS=, read -r -a f <<<"$line"
    ((${#f[@]} == 4)) || pp_die "line $n: write a wine as: name, bottles, from, until"
    local name count from until
    name=$(trim "${f[0]}") count=$(trim "${f[1]}")
    [[ $name =~ $re_name ]] || pp_die "line $n: a wine's name is letters, digits, spaces and ' ( ) . & / - (up to 60)"
    if [[ ! $count =~ ^[0-9]{1,4}$ ]] || ((10#$count < 1 || 10#$count > PP_MAX_BOTTLES)); then
      pp_die "line $n: bottles is a whole number from 1 to $PP_MAX_BOTTLES"
    fi
    from=$(pp_month "$(trim "${f[2]}")" 0) || pp_die "line $n: from is a year or a month, like 2027 or 2027-03"
    until=$(pp_month "$(trim "${f[3]}")" 1) || pp_die "line $n: until is a year or a month, like 2031 or 2031-06"
    ((from <= until)) || pp_die "line $n: the window ends before it starts"
    ((${#PP_NAME[@]} < PP_MAX_WINES)) || pp_die "the cellar list has more than $PP_MAX_WINES wines"
    total=$((total + 10#$count))
    ((total <= PP_MAX_BOTTLES)) || pp_die "the cellar has more than $PP_MAX_BOTTLES bottles"
    PP_NAME+=("$name") PP_COUNT+=($((10#$count))) PP_FROM+=("$from") PP_UNTIL+=("$until")
  done <<<"$text"
  ((${#PP_NAME[@]} > 0)) || pp_die 'no wines found: write a wine as: name, bottles, from, until'
}

# Checks the start and the span once the start is known (from the file or the command line).
pp_check_span() {
  local w last=0
  for w in "${!PP_NAME[@]}"; do ((PP_UNTIL[w] > last)) && last=${PP_UNTIL[w]}; done
  ((last - PP_START < PP_MAX_SPAN)) || pp_die 'the windows run more than 50 years past the start'
}

# Plans with `rate` bottles a month from PP_START, earliest end of window first: each month, open
# the bottles whose windows close soonest (ties: the wine with the most bottles left, then the one
# opened least this month, so a month mixes wines). For bottles that each take one slot, this
# finds a plan that misses nothing whenever one exists (an exchange argument; the tests also check
# it against trying every plan on small cellars).
# Sets PP_PLAN (one line per month: "month w w w"), PP_MISSED (per wine), PP_PAST (per wine,
# bottles whose window had already closed at the start).
pp_plan() {
  local rate=$1 t w k best last=0 left=() today=()
  PP_PLAN=() PP_MISSED=() PP_PAST=()
  for w in "${!PP_NAME[@]}"; do
    PP_MISSED[w]=0 PP_PAST[w]=0 left[w]=${PP_COUNT[w]}
    if ((PP_UNTIL[w] < PP_START)); then PP_PAST[w]=${left[w]} left[w]=0; fi
    ((PP_UNTIL[w] > last)) && last=${PP_UNTIL[w]}
  done
  for ((t = PP_START; t <= last; t++)); do
    local line=$t opened=0
    for w in "${!PP_NAME[@]}"; do today[w]=0; done
    for ((k = 0; k < rate; k++)); do
      best=-1
      for w in "${!PP_NAME[@]}"; do
        ((left[w] > 0 && PP_FROM[w] <= t)) || continue
        if ((best < 0)) || ((PP_UNTIL[w] < PP_UNTIL[best])) ||
          ((PP_UNTIL[w] == PP_UNTIL[best] && (today[w] < today[best] ||
            (today[w] == today[best] && left[w] > left[best])))); then
          best=$w
        fi
      done
      ((best >= 0)) || break
      left[best]=$((left[best] - 1)) today[best]=$((today[best] + 1)) opened=1
      line+=" $best"
    done
    ((opened)) && PP_PLAN+=("$line")
    # Anything whose window closes this month and is still in the rack has passed its best.
    for w in "${!PP_NAME[@]}"; do
      if ((PP_UNTIL[w] == t && left[w] > 0)); then PP_MISSED[w]=$((PP_MISSED[w] + left[w])) left[w]=0; fi
    done
  done
}

# The fewest bottles a month that opens everything in its window, and the stretch that forces it.
# A set of bottles fits only if every stretch of months can hold the bottles whose windows lie
# wholly inside it (Hall's condition for this kind of matching; for windows that are intervals,
# checking stretches is enough). For each possible first month a, sweep the windows in order of
# their end, adding those that start at or after a: O(wines^2).
# Sets PP_NEED, PP_CRUNCH_FROM, PP_CRUNCH_TO, PP_CRUNCH_BOTTLES.
pp_need() {
  local order a w cum need f
  PP_NEED=0 PP_CRUNCH_FROM='' PP_CRUNCH_TO='' PP_CRUNCH_BOTTLES=0
  mapfile -t order < <(for w in "${!PP_NAME[@]}"; do
    ((PP_UNTIL[w] >= PP_START)) && printf '%d %d\n' "${PP_UNTIL[w]}" "$w"
  done | sort -n -k1,1 -k2,2 | cut -d' ' -f2)
  local -A starts=()
  for w in "${order[@]}"; do
    f=${PP_FROM[w]}
    ((f < PP_START)) && f=$PP_START
    starts[$f]=1
  done
  for a in "${!starts[@]}"; do
    cum=0
    for w in "${order[@]}"; do
      f=${PP_FROM[w]}
      ((f < PP_START)) && f=$PP_START
      ((f >= a)) || continue
      cum=$((cum + PP_COUNT[w]))
      local months=$((PP_UNTIL[w] - a + 1))
      need=$(((cum + months - 1) / months))
      # The tightest stretch wins; among equals, the shortest (the clearest to explain).
      if ((need > PP_NEED || (need == PP_NEED && months < PP_CRUNCH_TO - PP_CRUNCH_FROM + 1))); then
        PP_NEED=$need PP_CRUNCH_FROM=$a PP_CRUNCH_TO=${PP_UNTIL[w]} PP_CRUNCH_BOTTLES=$cum
      fi
    done
  done
}
