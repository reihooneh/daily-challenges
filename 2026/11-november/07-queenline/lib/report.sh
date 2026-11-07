# shellcheck shell=bash
# The QL_* globals are set by ql_infer in lib/queenline.sh.
# shellcheck disable=SC2153
# Queenline's report: the story in words, what to do next, and a day-by-day timeline.
# Needs lib/queenline.sh, ql_parse and ql_infer first.

ql_span() { # a day range in words
  if (($1 == $2)); then ql_fmt "$1"; else printf '%s to %s' "$(ql_fmt "$1")" "$(ql_fmt "$2")"; fi
}

ql_report() {
  local today=$1 last=$((QL_N - 1))
  printf 'QUEENLINE  %s: %d inspection%s, %s\n' "$QL_NAME" "$QL_N" "$( ((QL_N == 1)) || printf s)" "$(ql_span "${QL_DAY[0]}" "${QL_DAY[last]}")"
  printf '\nWhat happened\n'
  case $QL_STATE in
    laying)
      printf '  The queen has been laying throughout: eggs at every inspection that looked.\n' ;;
    unknown)
      printf '  Not enough to go on. Note eggs or no-eggs at each inspection: eggs are the surest sign of a laying queen.\n' ;;
    laying-workers)
      if [[ -z $QL_STOP_LO ]]; then
        printf '  Drone brood in worker cells (several eggs to a cell, eggs on the cell walls) points to laying workers or a failing queen.\n'
      fi ;;
  esac
  if [[ -n $QL_STOP_LO ]]; then
    local why='the queen was lost or stopped laying'
    [[ $QL_CAUSE != swarm ]] || why='the colony swarmed and the old queen left with it'
    printf '  The old queen laid her last eggs %s: %s.\n' "$(ql_span "$QL_STOP_LO" "$QL_STOP_HI")" "$why"
  fi
  [[ -z $QL_CONFLICT ]] || printf '  Note: %s.\n' "$QL_CONFLICT"
  if [[ -n $QL_EMERGE_LO ]]; then
    if ((QL_EMERGENCY)); then
      printf '  No queen cells were recorded. If the bees raised emergency cells, a new queen emerged %s.\n' "$(ql_span "$QL_EMERGE_LO" "$QL_EMERGE_HI")"
    else
      printf '  The first new queen emerged (or will emerge) %s.\n' "$(ql_span "$QL_EMERGE_LO" "$QL_EMERGE_HI")"
    fi
    printf '  Mating flights: %s.\n' "$(ql_span "$QL_MATE_LO" "$QL_MATE_HI")"
  fi
  if [[ -n $QL_NEW_LO ]]; then
    printf '  A new queen started laying %s.\n' "$(ql_span "$QL_NEW_LO" "$QL_NEW_HI")"
  elif [[ -n $QL_LAY_LO ]]; then
    printf '  Her first eggs are due %s (most often about two weeks after she emerges).\n' "$(ql_span "$QL_LAY_LO" "$QL_LAY_HI")"
  fi
  if [[ -n $QL_DRY_LO ]]; then
    printf '  No capped worker brood %s: the varroa mites have nowhere to hide.\n' "$(ql_span "$QL_DRY_LO" "$QL_DRY_HI")"
  elif [[ -n $QL_STOP_LO && -n $QL_EMERGE_LO ]]; then
    printf '  The new brood starts before the old brood is all out, so there is no broodless gap.\n'
  fi

  printf '\nWhat to do (as of %s)\n' "$(ql_fmt "$today")"
  local said=0
  say() { printf '  - %s\n' "$1"; said=1; }
  case $QL_STATE in
    requeened)
      say 'The colony has a laying queen again. Check her brood pattern in a week: a solid, even pattern means she mated well.' ;;
    failed)
      say "No eggs by $(ql_fmt "$QL_LAY_HI"): the new queen has probably failed or been lost. Add a frame of eggs and young larvae from another colony as a test: queen cells on it within a few days mean the colony is queenless."
      say 'If no queen cells appear on the test frame, look for a virgin queen or laying workers before introducing a mated queen.' ;;
    late)
      say "Eggs are late. Give her until $(ql_fmt "$QL_LAY_HI"), then add a test frame of eggs from another colony." ;;
    laying-workers)
      say 'With laying workers the colony will not accept a queen easily: unite it with a queenright colony, or shake the bees out away from the hive.' ;;
    waiting|broken)
      if [[ -n $QL_MATE_LO ]] && ((today <= QL_MATE_HI)); then
        say "Leave the hive closed during mating flights, $(ql_span "$((today > QL_MATE_LO ? today : QL_MATE_LO))" "$QL_MATE_HI"): a disturbed virgin can be lost or killed."
      fi
      if [[ -n $QL_LAY_LO ]]; then
        local look=$((QL_EMERGE_HI + 21))
        ((look > today)) || look=$((today + 1))
        say "Look for eggs on $(ql_fmt "$look") or soon after; if there are none by $(ql_fmt "$QL_LAY_HI"), add a test frame of eggs."
      fi
      if [[ $QL_STATE == broken && -z $QL_EMERGE_LO ]]; then
        say 'Look for queen cells now: without them the colony cannot raise a queen. If there are none, add a frame of eggs from another colony.'
      fi
      if ((QL_EMERGENCY)); then
        say 'Record queen cells next time (cells-open, cells-capped, cells-hatched or no-cells): it pins down these dates.'
      fi ;;
  esac
  if [[ -n $QL_DRY_LO ]] && ((today <= QL_DRY_HI)); then
    # Treating means opening the hive, so not while a virgin queen may be out mating.
    local from=$((today > QL_DRY_LO ? today : QL_DRY_LO))
    if [[ -n $QL_MATE_HI && -z $QL_NEW_LO ]] && ((from <= QL_MATE_HI)); then from=$((QL_MATE_HI + 1)); fi
    if ((from <= QL_DRY_HI)); then
      say "Treat for varroa with oxalic acid while there is no capped brood, $(ql_span "$from" "$QL_DRY_HI") (after the mating flights; follow the product's label)."
    fi
  fi
  ((said)) || printf '  - Nothing urgent. Keep noting eggs, larvae, capped brood and queen cells at each inspection.\n'

  ql_timeline "$today"
}

# One column a day (two if the span is long): inspections, laying, capped brood and the new queen.
ql_timeline() {
  local today=$1 last=$((QL_N - 1)) d
  local start=$((QL_DAY[0])) end=$((QL_DAY[last] > today ? QL_DAY[last] : today))
  local v
  for v in "$QL_LAY_HI" "$QL_DRY_HI" "$QL_MATE_HI"; do [[ -z $v ]] || ((v <= end)) || end=$v; done
  ((end - start <= 180)) || end=$((start + 180))
  local step=1
  ((end - start <= 90)) || step=2
  local row_i='' row_l='' row_q='' row_b='' row_m=''
  local i
  for ((d = start; d <= end; d += step)); do
    local c=' '
    for ((i = 0; i < QL_N; i++)); do
      if ((QL_DAY[i] >= d && QL_DAY[i] < d + step)); then c='v'; fi
    done
    row_i="${row_i}$c"
    c='.'
    if [[ -n $QL_STOP_LO ]]; then
      if ((d <= QL_STOP_LO)); then c='='; elif ((d <= QL_STOP_HI)); then c='?'; else c=' '; fi
    elif [[ $QL_STATE == laying || $QL_STATE == laying-workers ]]; then c='='
    fi
    if [[ -n $QL_NEW_LO ]] && ((d >= QL_NEW_HI)); then c='='; elif [[ -n $QL_NEW_LO ]] && ((d >= QL_NEW_LO)); then c='?'; fi
    row_l="${row_l}$c"
    c=' '
    if [[ -n $QL_DRY_LO ]] && ((d >= QL_DRY_LO && d <= QL_DRY_HI)); then c='-'; fi
    row_b="${row_b}$c"
    c=' '
    if [[ -n $QL_EMERGE_LO ]]; then
      if ((d >= QL_EMERGE_LO && d <= QL_EMERGE_HI)); then c='E'
      elif ((d >= QL_MATE_LO && d <= QL_MATE_HI)); then c='m'
      fi
      if [[ -z $QL_NEW_LO ]] && ((d >= QL_LAY_LO && d <= QL_LAY_HI)) && [[ $c == ' ' ]]; then c='L'; fi
    fi
    row_q="${row_q}$c"
    if (((d - start) % (7 * step) == 0)); then row_m="${row_m}|"; else row_m="${row_m} "; fi
  done
  printf '\nTimeline, %s to %s (one column %s; | every %s)\n' "$(ql_fmt "$start")" "$(ql_fmt "$end")" "$( ((step == 1)) && printf 'a day' || printf 'every 2 days')" "$( ((step == 1)) && printf 'week' || printf '2 weeks')"
  printf '  %-13s %s\n' 'weeks' "$row_m" 'inspections' "$row_i" 'queen laying' "$row_l" 'no brood' "$row_b" 'new queen' "$row_q"
  printf '  %-13s %s\n' '' "= laying  ? sometime here  - no capped brood  E emerges  m mating  L first eggs due"
}
