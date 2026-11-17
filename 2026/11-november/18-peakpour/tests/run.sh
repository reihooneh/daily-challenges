#!/usr/bin/env bash
# Tests for Peakpour. Run from anywhere:  bash tests/run.sh
# shellcheck source-path=SCRIPTDIR
# Checks pass code to 'bash -c' in single quotes on purpose, with arguments after it (SC2016).
# shellcheck disable=SC2016
set -uo pipefail
export LC_ALL=C.UTF-8

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin/peakpour"
LIB="$HERE/../lib/peakpour.sh"
# shellcheck source=../lib/peakpour.sh
source "$LIB"
passed=0 failed=0

check() { # description, then a command that must succeed
  local what=$1; shift
  if "$@"; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  %s\n' "$what"; fi
}

# Runs peakpour on text given as an argument (extra arguments follow); sets OUT, ERR and CODE.
run() {
  local text=$1 errf; shift
  errf=$(mktemp)
  OUT=$(printf '%s' "$text" | "$BIN" - "$@" 2>"$errf")
  CODE=$?
  ERR=$(<"$errf")
  rm -f -- "$errf"
}
has() { [[ $OUT == *"$1"* ]]; }
err_has() { [[ $ERR == *"$1"* ]]; }
refused() { run "$1"; ((CODE == 2)) && err_has "$2"; }

# ---------- Months ----------
check 'a year starts in January' [ "$(pp_month 2026 0)" = $((2026 * 12)) ]
check 'a year ends in December' [ "$(pp_month 2026 1)" = $((2026 * 12 + 11)) ]
check 'a month' [ "$(pp_month 2027-03 0)" = $((2027 * 12 + 2)) ]
check 'leading zero is not octal' [ "$(pp_month 2027-08 0)" = $((2027 * 12 + 7)) ]
check 'no month 13' bash -c 'source "$1"; ! pp_month 2026-13 0' _ "$LIB"
check 'no two-digit years' bash -c 'source "$1"; ! pp_month 26 0' _ "$LIB"
check 'no year 1900' bash -c 'source "$1"; ! pp_month 1900 0' _ "$LIB"
check 'no shell in a month' bash -c 'source "$1"; ! pp_month "\$(id)" 0' _ "$LIB"
check 'formatted' [ "$(pp_fmt $((2026 * 12 + 10)))" = 'Nov 2026' ]

# ---------- Reading a cellar ----------
pp_parse $'start 2026-11\nrate 2\n# a comment\nShiraz 2016, 6, 2024, 2034  # trailing comment\nRose, 2, 2026-01, 2027-03\r\n'
check 'two wines' [ "${#PP_NAME[@]}" = 2 ]
check 'start and rate' [ "$PP_START" = $((2026 * 12 + 10)) ] && [ "$PP_RATE" = 2 ]
check 'fields' [ "${PP_NAME[1]}" = Rose ] && [ "${PP_COUNT[0]}" = 6 ] && [ "${PP_UNTIL[1]}" = $((2027 * 12 + 2)) ]

check 'no wines' refused $'start 2026-11\n' 'no wines found'
check 'three fields' refused $'start 2026-11\nRose, 2, 2026\n' 'line 2: write a wine as'
check 'five fields' refused $'start 2026-11\nRose, 2, 2026, 2027, x\n' 'line 2: write a wine as'
check 'zero bottles' refused $'Rose, 0, 2026, 2027\n' 'bottles is a whole number'
check 'too many bottles' refused $'Rose, 2001, 2026, 2027\n' 'bottles is a whole number'
check 'window backwards' refused $'Rose, 2, 2028, 2027\n' 'ends before it starts'
check 'bad from' refused $'Rose, 2, soon, 2027\n' 'from is a year or a month'
check 'bad rate' refused $'rate 0\nRose, 2, 2026, 2027\n' 'rate is 1 to 100'
check 'shell in a name' refused $'$(touch /tmp/peakpour-pwned), 2, 2026, 2027\n' "a wine's name"
check '...and nothing ran' [ ! -e /tmp/peakpour-pwned ]
check 'backticks in a name' refused $'`id`, 2, 2026, 2027\n' "a wine's name"
check 'control character' refused $'Rose\e[31m, 2, 2026, 2027\n' 'control character'
check 'invalid UTF-8' refused $'Ros\xe9, 2, 2026, 2027\n' 'not valid UTF-8'
check 'long line' refused "$(printf 'R%.0s' {1..201}), 2, 2026, 2027" 'longer than 200'
check 'too big' refused "$(head -c 65537 /dev/zero | tr '\0' 'x')" 'larger than 64 KB'
many=$(for i in {1..201}; do printf 'Wine %d, 1, 2026, 2027\n' "$i"; done)
check 'too many wines' refused "start 2026-11"$'\n'"$many" 'more than 200 wines'
check 'too many bottles in all' refused $'start 2026-11\nA, 1500, 2026, 2030\nB, 600, 2026, 2030\n' 'more than 2000 bottles'
check 'no start' refused $'Rose, 2, 2026, 2027\n' 'say when to start'
check 'span over 50 years' refused $'start 2026-11\nPort, 1, 2026, 2099\n' 'more than 50 years'

# ---------- Planning: against an exact matching on small cellars ----------
# Most bottles that can be opened in their windows with r a month = a maximum bipartite matching
# between bottles and month slots (Kuhn's augmenting paths), worked out independently of Peakpour.
declare -a B_FROM B_UNTIL SLOT_OWNER SEEN
augment() { # bottle -> 0 if placed
  local b=$1 m s
  for ((m = B_FROM[b]; m <= B_UNTIL[b]; m++)); do
    for ((s = m * R; s < (m + 1) * R; s++)); do
      ((SEEN[s])) && continue
      SEEN[s]=1
      if ((SLOT_OWNER[s] < 0)) || augment "${SLOT_OWNER[s]}"; then SLOT_OWNER[s]=$b; return 0; fi
    done
  done
  return 1
}
most_in_time() { # rate -> prints the most bottles that can be opened in their windows
  R=$1
  local w c b=0 s placed=0 months=$((LAST - PP_START + 1))
  B_FROM=() B_UNTIL=() SLOT_OWNER=()
  for w in "${!PP_NAME[@]}"; do
    for ((c = 0; c < PP_COUNT[w]; c++)); do
      B_FROM[b]=$((PP_FROM[w] < PP_START ? 0 : PP_FROM[w] - PP_START)) B_UNTIL[b]=$((PP_UNTIL[w] - PP_START)); b=$((b + 1))
    done
  done
  for ((s = 0; s < months * R; s++)); do SLOT_OWNER[s]=-1; done
  for ((c = 0; c < b; c++)); do
    SEEN=()
    for ((s = 0; s < months * R; s++)); do SEEN[s]=0; done
    augment "$c" && placed=$((placed + 1))
  done
  printf '%d' "$placed"
}
missed() { local w m=0; for w in "${!PP_NAME[@]}"; do m=$((m + PP_MISSED[w])); done; printf '%d' "$m"; }

RANDOM=11
bad=0 badneed=0
for _ in {1..60}; do
  text="start 2030-01"$'\n'
  nw=$((RANDOM % 4 + 2)) total=0
  for ((w = 0; w < nw; w++)); do
    a=$((RANDOM % 5)) len=$((RANDOM % 3)) c=$((RANDOM % 3 + 1))
    text+="Wine $w, $c, 2030-0$((a + 1)), 2030-0$((a + len + 1))"$'\n'
    total=$((total + c))
  done
  pp_parse "$text"
  LAST=0
  for w in "${!PP_NAME[@]}"; do ((PP_UNTIL[w] > LAST)) && LAST=${PP_UNTIL[w]}; done
  for r in 1 2; do
    pp_plan "$r"
    best=$(most_in_time "$r")
    if (($(missed) != total - best)); then
      bad=$((bad + 1))
      ((bad == 1)) && printf '  first mismatch (rate %d):\n%s' "$r" "$text"
    fi
  done
  pp_need
  pp_plan "$PP_NEED"
  (($(missed) == 0)) || badneed=$((badneed + 1))
  if ((PP_NEED > 1)); then
    pp_plan $((PP_NEED - 1))
    (($(missed) > 0)) || badneed=$((badneed + 1))
  fi
done
check "the plan misses no more than the best possible ($bad of 120 differ)" [ "$bad" = 0 ]
check "the pace needed is exactly enough ($badneed wrong)" [ "$badneed" = 0 ]

# ---------- The examples and the command line ----------
OUT=$("$BIN" "$HERE/../examples/cellar.txt"); CODE=$?
check 'example: one Beaujolais passes its best' [ "$CODE" = 3 ]
check 'example: named' has 'Beaujolais 2023: 1 of 3, window closes Dec 2026'
check 'example: the pace needed' has 'you need 3 a month'
check 'example: soonest first' has 'Dec 2026  Beaujolais 2023 x2'
OUT=$("$BIN" "$HERE/../examples/cellar.txt" --rate 3); CODE=$?
check 'at 3 a month nothing is missed' [ "$CODE" = 0 ]
check '...and it says so' has 'Every bottle is opened inside its drinking window.'
run $'Rose, 2, 2026, 2027\n' --start 2026-06
check 'start on the command line, rate worked out' [ "$CODE" = 0 ] && has '1 a month from Jun 2026'
run $'start 2028-01\nRose, 2, 2026, 2027\nShiraz, 1, 2026, 2030\n'
check 'a window already closed' [ "$CODE" = 3 ] && has 'Rose: 2 bottles, window closed Dec 2027'
run $'start 2026-01\nRose, 1, 2026, 2027\n' --rate 0
check 'bad --rate' [ "$CODE" = 2 ] && err_has '--rate is 1 to 100'
run $'Rose, 1, 2026, 2027\n' --start 'next week'
check 'bad --start' [ "$CODE" = 2 ] && err_has '--start is a month'
"$BIN" >/dev/null 2>&1; check 'usage' [ $? = 2 ]
"$BIN" a b >/dev/null 2>&1; check 'two files' [ $? = 2 ]
tmp=$(mktemp -d)
ln -s "$HERE/../examples/cellar.txt" "$tmp/link.txt"
"$BIN" "$tmp/link.txt" >/dev/null 2>&1; check 'links refused' [ $? = 2 ]
"$BIN" "$tmp" >/dev/null 2>&1; check 'folders refused' [ $? = 2 ]
"$BIN" "$tmp/none.txt" >/dev/null 2>&1; check 'missing file' [ $? = 2 ]
rm -rf -- "$tmp"

# ---------- The biggest cellar ----------
big="start 2026-01"$'\n'"$(for i in {1..200}; do printf 'Wine %d, 10, %d, %d\n' "$i" $((2026 + i % 10)) $((2036 + i % 13)); done)"
start=$SECONDS
run "$big"
check "200 wines and 2,000 bottles in $((SECONDS - start)) s" [ "$CODE" = 0 ] && ((SECONDS - start < 60))

printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
