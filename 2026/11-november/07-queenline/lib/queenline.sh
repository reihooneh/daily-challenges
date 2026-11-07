# shellcheck shell=bash
# The results are globals read by lib/report.sh and the tests, so 'unused' warnings don't apply.
# shellcheck disable=SC2034
# Queenline's library: reading an inspection log and working out what happened to the queen.
# Sourced by bin/queenline and by the tests. Dates are handled as whole days since 1970-01-01 (UTC).
#
# Honey bee development (Apis mellifera, in days from the egg being laid):
#   worker: egg until day 3, open larva until day 9 (then capped), emerges on day 21
#   queen:  egg until day 3, open cell until day 8 (then capped), emerges on day 16
# A new queen flies to mate from about 5 days after emerging, and starts laying 10 to 28 days
# after emerging (usually around two weeks).

readonly QL_MAX_BYTES=65536 QL_MAX_LINE=200 QL_MAX_INSPECTIONS=200
readonly QL_TOKENS=' eggs no-eggs larvae no-larvae capped no-capped no-brood queen virgin cells-open cells-capped cells-hatched no-cells drone-laying swarm '

ql_die() { printf 'queenline: %s\n' "$1" >&2; exit 2; }

# YYYY-MM-DD to a day number, refusing anything that isn't a real date from 2000 to 2099.
ql_day() {
  local d=$1 s
  [[ $d =~ ^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || return 1
  s=$(date -u -d "$d" +%s 2>/dev/null) || return 1
  [[ $(date -u -d "@$s" +%F) == "$d" ]] || return 1
  printf '%d' $((s / 86400))
}

# A day number to "Sat 7 Nov".
ql_fmt() { date -u -d "@$(($1 * 86400))" '+%a %-d %b'; }

# Reads the log text into global arrays: QL_DAY, and per-inspection fields that are 1, 0 or empty
# (not recorded): QL_EGGS QL_LARVAE QL_CAPPED QL_QUEEN QL_VIRGIN QL_DRONE QL_SWARM, and QL_CELLS
# (open, capped, hatched, none or empty). Errors give the line number, never the line.
ql_parse() {
  local text=$1 line n=0 i=-1 w d prev=''
  local re_name="^[A-Za-z0-9][A-Za-z0-9 '().,&-]{0,39}$"
  QL_NAME='My hive'
  QL_DAY=() QL_EGGS=() QL_LARVAE=() QL_CAPPED=() QL_QUEEN=() QL_VIRGIN=() QL_DRONE=() QL_SWARM=() QL_CELLS=()
  ((${#text} <= QL_MAX_BYTES)) || ql_die 'the log is larger than 64 KB'
  # Control characters (except tab) and invisible formatting characters, in their UTF-8 forms.
  if LC_ALL=C grep -q $'[\x01-\x08\x0b-\x1f\x7f]' <<<"$text" ||
    LC_ALL=C grep -qE $'\xe2\x80[\x8b-\x8f\xaa-\xae]|\xe2\x81[\xa0-\xaf]|\xef\xbb\xbf' <<<"$text"; then
    ql_die 'the log has a control or invisible formatting character'
  fi
  iconv -f UTF-8 -t UTF-8 <<<"$text" >/dev/null 2>&1 || ql_die 'the log is not valid UTF-8 text'
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    ((${#line} <= QL_MAX_LINE)) || ql_die "line $n: is longer than $QL_MAX_LINE characters"
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n $line ]] || continue
    if [[ $line == hive[[:space:]]* ]]; then
      local nm=${line#hive}
      nm=${nm#"${nm%%[![:space:]]*}"}
      [[ $nm =~ $re_name ]] || ql_die "line $n: a hive's name is letters, digits, spaces and ' ( ) . , & - (up to 40)"
      ((i < 0)) || ql_die "line $n: name the hive before the first inspection"
      QL_NAME=$nm
      continue
    fi
    read -r -a w <<<"$line"
    d=$(ql_day "${w[0]}") || ql_die "line $n: an inspection starts with a real date, like 2026-11-07"
    [[ -z $prev ]] || ((d > prev)) || ql_die "line $n: inspections must be in date order, one a day"
    ((i + 1 < QL_MAX_INSPECTIONS)) || ql_die "at most $QL_MAX_INSPECTIONS inspections"
    prev=$d
    i=$((i + 1))
    QL_DAY[i]=$d QL_EGGS[i]='' QL_LARVAE[i]='' QL_CAPPED[i]='' QL_QUEEN[i]='' QL_VIRGIN[i]='' QL_DRONE[i]='' QL_SWARM[i]='' QL_CELLS[i]=''
    ((${#w[@]} > 1)) || ql_die "line $n: say what you saw, like 'eggs capped queen'"
    local t
    for t in "${w[@]:1}"; do
      [[ $QL_TOKENS == *" $t "* ]] || ql_die "line $n: words are:$QL_TOKENS"
      case $t in
        eggs) QL_EGGS[i]=1 ;; no-eggs) QL_EGGS[i]=0 ;;
        larvae) QL_LARVAE[i]=1 ;; no-larvae) QL_LARVAE[i]=0 ;;
        capped) QL_CAPPED[i]=1 ;; no-capped) QL_CAPPED[i]=0 ;;
        no-brood) QL_EGGS[i]=0 QL_LARVAE[i]=0 QL_CAPPED[i]=0 ;;
        queen) QL_QUEEN[i]=1 ;; virgin) QL_VIRGIN[i]=1 ;;
        cells-open) QL_CELLS[i]=open ;; cells-capped) QL_CELLS[i]=capped ;;
        cells-hatched) QL_CELLS[i]=hatched ;; no-cells) QL_CELLS[i]=none ;;
        drone-laying) QL_DRONE[i]=1 ;; swarm) QL_SWARM[i]=1 ;;
      esac
    done
  done <<<"$text"
  ((i >= 0)) || ql_die 'the log has no inspections'
  QL_N=$((i + 1))
}

# Works out the story. Sets QL_* results (day numbers, or empty when there is no answer):
#   QL_STOP_LO/HI  when the old queen laid her last egg     QL_CAUSE   swarm, loss or ''
#   QL_NEW_LO/HI   when a new queen laid her first egg      QL_EMERGE_LO/HI  when a new queen emerged
#   QL_MATE_LO/HI  mating flights      QL_LAY_LO/HI  first eggs expected      QL_DRY_LO/HI  no capped brood
#   QL_STATE       laying, broken, waiting, late, failed, requeened, laying-workers or unknown
ql_infer() {
  local i d lo hi
  QL_STOP_LO='' QL_STOP_HI='' QL_CAUSE='' QL_NEW_LO='' QL_NEW_HI='' QL_EMERGE_LO='' QL_EMERGE_HI=''
  QL_MATE_LO='' QL_MATE_HI='' QL_LAY_LO='' QL_LAY_HI='' QL_DRY_LO='' QL_DRY_HI='' QL_STATE=unknown QL_CONFLICT=''
  local last=$((QL_N - 1))

  # The latest run of inspections with no eggs, and the eggs that may follow it.
  local run_end=-1 run_start=-1
  for ((i = last; i >= 0; i--)); do
    if [[ ${QL_EGGS[i]} == 0 ]]; then run_end=$i; break; fi
  done
  if ((run_end < 0)); then
    QL_STATE=laying
    [[ ${QL_EGGS[last]} == 1 ]] || QL_STATE=unknown
    for ((i = 0; i < QL_N; i++)); do [[ ${QL_DRONE[i]} != 1 ]] || QL_STATE=laying-workers; done
    return 0
  fi
  run_start=$run_end
  while ((run_start > 0)) && [[ ${QL_EGGS[run_start - 1]} != 1 ]]; do run_start=$((run_start - 1)); done
  local new=-1
  for ((i = run_end + 1; i <= last; i++)); do
    if [[ ${QL_EGGS[i]} == 1 ]]; then new=$i; break; fi
  done

  # When the old queen stopped: every brood stage seen gives a range in which an egg was laid
  # (so she was still laying at its start); every stage seen absent gives a range with no eggs.
  lo='' hi=''
  for ((i = 0; i <= run_end; i++)); do
    d=${QL_DAY[i]}
    [[ ${QL_EGGS[i]} != 1 ]] || { ((d - 3 > ${lo:--99999})) && lo=$((d - 3)); }
    [[ ${QL_LARVAE[i]} != 1 ]] || { ((d - 9 > ${lo:--99999})) && lo=$((d - 9)); }
    [[ ${QL_CAPPED[i]} != 1 ]] || { ((d - 21 > ${lo:--99999})) && lo=$((d - 21)); }
  done
  if [[ -z $lo ]]; then
    QL_STATE=unknown
    QL_CONFLICT='the log has no sign of a laying queen before the eggs stopped'
  else
    for ((i = run_start; i <= run_end; i++)); do
      d=${QL_DAY[i]}
      local c
      for c in "${QL_EGGS[i]}:3" "${QL_LARVAE[i]}:9" "${QL_CAPPED[i]}:21"; do
        [[ ${c%%:*} == 0 ]] || continue
        local cand=$((d - ${c#*:}))
        ((cand >= lo)) || continue
        [[ -n $hi ]] && ((cand >= hi)) || hi=$cand
      done
    done
    [[ -n $hi ]] || { hi=$((QL_DAY[run_start] - 3)); ((hi >= lo)) || QL_CONFLICT='the brood seen does not fit one stop in laying'; }
    ((hi >= lo)) || hi=$lo
    QL_STOP_LO=$lo QL_STOP_HI=$hi
  fi

  QL_CAUSE=loss
  local cells_seen=0
  for ((i = 0; i <= (new < 0 ? last : new); i++)); do
    [[ ${QL_SWARM[i]} != 1 ]] || QL_CAUSE=swarm
    [[ ${QL_CELLS[i]} != open && ${QL_CELLS[i]} != capped ]] || cells_seen=1
  done
  # Swarm cells are started while the old queen is still laying; emergency cells only after she has gone.
  if ((cells_seen)) && [[ -n $QL_STOP_HI ]]; then
    for ((i = 0; i < run_start; i++)); do
      [[ ${QL_CELLS[i]} != open && ${QL_CELLS[i]} != capped ]] || QL_CAUSE=swarm
    done
  fi

  # When the first new queen emerges. Of several queen cells the first to emerge counts, so take the
  # earliest of the bounds; a queen seen, a hatched cell or new eggs cap it.
  lo='' hi=''
  local from=${QL_STOP_LO:-${QL_DAY[run_start]}}
  for ((i = 0; i <= last; i++)); do
    d=${QL_DAY[i]}
    ((d >= from - 16)) || continue
    local l='' h=''
    case ${QL_CELLS[i]} in
      open) l=$((d + 8)) h=$((d + 16)) ;;
      capped) l=$d h=$((d + 8)) ;;
      hatched) l=$((d - 14)) h=$d ;;
    esac
    [[ ${QL_VIRGIN[i]} != 1 ]] || { l=$((d - 7)) h=$d; }
    [[ -n $l ]] || continue
    { [[ -z $lo ]] || ((l < lo)); } && lo=$l
    { [[ -z $hi ]] || ((h < hi)); } && hi=$h
  done
  if [[ -z $lo && -n $QL_STOP_LO && $QL_CAUSE == loss ]]; then
    # No cells recorded: if the bees raised emergency cells from young larvae, these emerge 10 to 13 days on.
    lo=$((QL_STOP_LO + 10)) hi=$((QL_STOP_HI + 13))
    QL_EMERGENCY=1
  else
    QL_EMERGENCY=0
  fi
  if ((new >= 0)); then
    QL_NEW_LO=$((QL_DAY[run_end] + 1)) QL_NEW_HI=${QL_DAY[new]}
    { [[ -z $hi ]] || ((QL_NEW_HI - 10 < hi)); } && hi=$((QL_NEW_HI - 10))
  fi
  if [[ -n $lo ]]; then
    ((lo <= hi)) || lo=$hi
    QL_EMERGE_LO=$lo QL_EMERGE_HI=$hi
    QL_MATE_LO=$((lo + 5)) QL_MATE_HI=$((hi + 14))
    QL_LAY_LO=$((lo + 10)) QL_LAY_HI=$((hi + 28))
    # No eggs seen yet means none laid before the day after the last look.
    # (If the last look was after the latest date, she is overdue: the window stays, and is past.)
    if ((new < 0)) && ((QL_LAY_LO <= QL_DAY[run_end] && QL_DAY[run_end] < QL_LAY_HI)); then
      QL_LAY_LO=$((QL_DAY[run_end] + 1))
    fi
  fi

  # No capped worker brood: from when the old queen's last brood has emerged (21 days after her last
  # egg), until the day before the new queen's first brood is capped (9 days after her first egg).
  if [[ -n $QL_STOP_HI ]]; then
    local dry_end=''
    if [[ -n $QL_NEW_LO ]]; then
      dry_end=$((QL_NEW_LO + 8))
    elif [[ -n $QL_LAY_LO ]]; then
      # Not laying yet: her first egg comes after the last look with no eggs, and not before LAY_LO.
      dry_end=$(((QL_LAY_LO > QL_DAY[run_end] ? QL_LAY_LO : QL_DAY[run_end] + 1) + 8))
    fi
    if [[ -n $dry_end ]] && ((QL_STOP_HI + 21 <= dry_end)); then
      QL_DRY_LO=$((QL_STOP_HI + 21)) QL_DRY_HI=$dry_end
    fi
  fi

  # Where things stand at the last inspection.
  local today=${QL_DAY[last]} drone=0
  for ((i = run_start; i <= last; i++)); do [[ ${QL_DRONE[i]} != 1 ]] || drone=1; done
  if ((new >= 0)); then QL_STATE=requeened
  elif ((drone)); then QL_STATE=laying-workers
  elif [[ -n $QL_LAY_HI ]] && ((today >= QL_LAY_HI)); then QL_STATE=failed
  elif [[ -n $QL_LAY_LO ]] && ((today > QL_LAY_LO + 14)); then QL_STATE=late
  elif [[ -n $QL_EMERGE_LO ]]; then QL_STATE=waiting
  else QL_STATE=broken
  fi
  return 0
}
