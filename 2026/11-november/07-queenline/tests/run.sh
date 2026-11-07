#!/usr/bin/env bash
# Tests for Queenline. Run from anywhere:  bash tests/run.sh
# shellcheck source-path=SCRIPTDIR
# Checks pass code to 'bash -c' in single quotes on purpose, with arguments after it (SC2016).
# shellcheck disable=SC2016
set -uo pipefail
export LC_ALL=C.UTF-8

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin/queenline"
# shellcheck source=../lib/queenline.sh
source "$HERE/../lib/queenline.sh"
passed=0 failed=0

check() { # description, then a command that must succeed
  local what=$1; shift
  if "$@"; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  %s\n' "$what"; fi
}

# Runs queenline on text given as an argument (extra arguments follow); sets OUT, ERR and CODE.
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
day() { ql_day "$1"; }
infer() { ql_parse "$1"; ql_infer; }

# ---------- Dates ----------
check 'a real date' [ "$(day 2026-11-07)" = "$((($(date -u -d 2026-11-07 +%s)) / 86400))" ]
check 'no 30 February' bash -c 'source "$1"; ! ql_day 2026-02-30' _ "$HERE/../lib/queenline.sh"
check 'no year 1999' bash -c 'source "$1"; ! ql_day 1999-01-01' _ "$HERE/../lib/queenline.sh"
check 'no date words' bash -c 'source "$1"; ! ql_day "next friday"' _ "$HERE/../lib/queenline.sh"
check 'formatted' [ "$(ql_fmt "$(day 2026-11-07)")" = 'Sat 7 Nov' ]

# ---------- Worked by hand ----------
infer $'2026-01-01 eggs\n2026-01-08 no-eggs larvae'
# eggs on 1 Jan: an egg after 29 Dec. Larvae on 8 Jan: an egg 30 Dec to 5 Jan. No eggs on 8 Jan: none after 5 Jan.
check 'stop: 30 Dec to 5 Jan' [ "$QL_STOP_LO,$QL_STOP_HI" = "$(day 2025-12-30),$(day 2026-01-05)" ]
check 'no cells recorded: queen lost' [ "$QL_CAUSE" = loss ]
check 'emergency cells estimated 10 to 13 days on' [ "$QL_EMERGENCY,$QL_EMERGE_LO,$QL_EMERGE_HI" = "1,$(day 2026-01-09),$(day 2026-01-18)" ]

infer $'2026-03-01 eggs larvae capped\n2026-03-08 eggs cells-capped\n2026-03-15 no-eggs larvae capped cells-capped\n2026-03-22 no-eggs no-larvae capped'
check 'cells before the stop: a swarm' [ "$QL_CAUSE" = swarm ]
check 'capped cells on 8 Mar: a queen by 16 Mar' [ "$QL_EMERGE_LO,$QL_EMERGE_HI" = "$(day 2026-03-08),$(day 2026-03-16)" ]

infer $'2026-03-01 eggs\n2026-03-08 no-eggs cells-capped\n2026-03-29 no-eggs\n2026-04-05 eggs larvae'
check 'eggs again: requeened' [ "$QL_STATE" = requeened ]
check 'her first egg after 29 Mar, by 5 Apr' [ "$QL_NEW_LO,$QL_NEW_HI" = "$(day 2026-03-30),$(day 2026-04-05)" ]
check 'broodless until the day before her first brood is capped' [ "$QL_DRY_HI" = "$(day 2026-04-07)" ]

infer $'2026-03-01 eggs\n2026-03-08 no-eggs cells-capped\n2026-04-20 no-eggs no-larvae no-capped'
check 'no eggs long after: failed' [ "$QL_STATE" = failed ]
infer $'2026-03-01 eggs\n2026-03-08 no-eggs\n2026-03-20 no-eggs drone-laying'
check 'drone laying: laying workers' [ "$QL_STATE" = laying-workers ]
infer $'2026-03-01 eggs\n2026-03-08 eggs queen'
check 'eggs throughout: laying' [ "$QL_STATE" = laying ]

# ---------- Simulated colonies ----------
# A colony whose queen lays every day to day S, then swarms; one swarm cell started on S-6 (so
# the new queen emerges on E = S+10), and she lays from F = E+m, m 10 to 28. A beekeeper looks
# every 5 to 9 days and writes down exactly what is there. Every window Queenline infers must
# contain the truth, and its broodless window must truly have no capped brood.
sim_ok=1 sim_n=0
RANDOM=42
for round in $(seq 1 150); do
  base=$(day 2026-09-01)
  S=$((base + 20 + RANDOM % 15))
  c=$((S - 6)) E=$((S + 10)) F=$((S + 10 + 10 + RANDOM % 19))
  log='' d=$((base + RANDOM % 5))
  while ((d < F + 12)) && ((${#log} < 4000)); do
    egg=0 larva=0 capd=0
    for ((t = d - 20; t <= d; t++)); do
      if ((t <= S || t >= F)); then
        ((t > d - 3)) && egg=1
        ((t > d - 9 && t <= d - 3)) && larva=1
        ((t > d - 21 && t <= d - 9)) && capd=1
      fi
    done
    line="$(date -u -d "@$((d * 86400))" +%F)"
    line+=" $( ((egg)) && echo eggs || echo no-eggs) $( ((larva)) && echo larvae || echo no-larvae) $( ((capd)) && echo capped || echo no-capped)"
    if ((d >= c && d < c + 8)); then line+=' cells-open'
    elif ((d >= c + 8 && d < c + 16)); then line+=' cells-capped'
    elif ((d >= c + 16 && d < c + 30)); then line+=' cells-hatched'
    fi
    ((d >= E && d < E + 7)) && line+=' virgin'
    log+="$line"$'\n'
    d=$((d + 5 + RANDOM % 5))
  done
  infer "$log"
  sim_n=$((sim_n + 1))
  ok=1
  [[ -n $QL_STOP_LO ]] && ((QL_STOP_LO <= S && S <= QL_STOP_HI)) || ok=0
  [[ -n $QL_EMERGE_LO ]] && ((QL_EMERGE_LO <= E && E <= QL_EMERGE_HI)) || ok=0
  if [[ -n $QL_NEW_LO ]]; then ((QL_NEW_LO <= F && F <= QL_NEW_HI)) || ok=0; fi
  if [[ -n $QL_DRY_LO ]]; then
    for ((x = QL_DRY_LO; x <= QL_DRY_HI; x++)); do
      # capped brood on day x: an egg laid after x-21 and by x-9
      for ((t = x - 20; t <= x - 9; t++)); do ((t <= S || t >= F)) && ok=0; done
    done
  fi
  if ((!ok)); then
    sim_ok=0
    printf 'simulation %d: S=%s E=%s F=%s  got stop %s-%s emerge %s-%s new %s-%s dry %s-%s\n%s' "$round" "$S" "$E" "$F" "$QL_STOP_LO" "$QL_STOP_HI" "$QL_EMERGE_LO" "$QL_EMERGE_HI" "$QL_NEW_LO" "$QL_NEW_HI" "$QL_DRY_LO" "$QL_DRY_HI" "$log"
    break
  fi
done
check "every window contains the truth, in $sim_n simulated colonies" [ "$sim_ok" = 1 ]

# ---------- The command line ----------
run "$(<"$HERE/../examples/blue-hive.txt")"
check 'the example runs' [ "$CODE" = 0 ]
check 'title' has 'QUEENLINE  Blue hive: 6 inspections, Sat 3 Oct to Sat 7 Nov'
check 'the swarm' has 'The old queen laid her last eggs Sat 10 Oct to Wed 14 Oct: the colony swarmed'
check 'emergence' has 'The first new queen emerged (or will emerge) Sat 17 Oct to Sun 25 Oct.'
check 'leave her to mate' has 'Leave the hive closed during mating flights, Sat 7 Nov to Sun 8 Nov'
check 'treat after mating, while broodless' has 'Treat for varroa with oxalic acid while there is no capped brood, Mon 9 Nov to Mon 16 Nov'
check 'timeline' has 'new queen                   EEEEEEEEE'
run "$(<"$HERE/../examples/blue-hive.txt")" --today 2026-11-12
check 'planning from a later day' has 'What to do (as of Thu 12 Nov)'
run "$(<"$HERE/../examples/blue-hive.txt")" --today 2026-11-01
check 'today before the last inspection is refused' err_has 'must not be before'
run $'2026-03-01 eggs\n2026-03-08 no-eggs cells-capped\n2026-04-20 no-eggs no-larvae no-capped'
check 'a failed queen: test frame' has 'Add a frame of eggs and young larvae from another colony as a test'

dir=$(mktemp -d)
ln -s "$HERE/../examples/blue-hive.txt" "$dir/link.txt"
"$BIN" "$dir/link.txt" >/dev/null 2>"$dir/err"; code=$?
check 'a symbolic link is refused' [ "$code" = 2 ]
"$BIN" "$dir" >/dev/null 2>"$dir/err"; code=$?
check 'a folder is refused' [ "$code" = 2 ]
"$BIN" "$dir/secret-name-zz.txt" >/dev/null 2>"$dir/err"; code=$?
check 'the path is never echoed' bash -c '[ "$1" = 2 ] && ! grep -q secret-name "$2"' _ "$code" "$dir/err"
rm -rf -- "$dir"

bad() { # text, expected message fragment
  run "$1"
  check "refused: $2" bash -c '[ "$1" = 2 ] && [[ $2 == *"$3"* ]] && [[ $2 != *SECRET* ]]' _ "$CODE" "$ERR" "$2"
}
bad '' 'no inspections'
bad 'hive Blue' 'no inspections'
bad $'2026-11-07' 'say what you saw'
bad $'2026-11-07 eggs rm -rf SECRET' 'words are'
bad $'2026-11-07 $(touch SECRET)' 'words are'
bad $'2026-02-30 eggs' 'a real date'
bad $'yesterday eggs' 'a real date'
bad $'2026-11-07 eggs\n2026-11-01 eggs' 'date order'
bad $'2026-11-07 eggs\nhive Late' 'before the first inspection'
bad $'hive <script>SECRET\n2026-11-07 eggs' "hive's name"
bad $'hive Blue\xe2\x80\xaeSECRET\n2026-11-07 eggs' 'invisible formatting'
bad $'2026-11-07 eggs\x1b[2J' 'control'
bad $'2026-11-07 eggs \xff' 'UTF-8'
bad "# $(printf 'x%.0s' $(seq 1 250))"$'\n2026-11-07 eggs' 'longer than 200'
many=$(for i in $(seq 0 200); do date -u -d "2026-01-01 +$i days" '+%F eggs'; done)
bad "$many" 'at most 200'
bad "$(head -c 70000 /dev/zero | tr '\0' '#')" '64 KB'
"$BIN" >/dev/null 2>&1; check 'usage without a log' [ $? = 2 ]
"$BIN" - --bogus </dev/null >/dev/null 2>&1; check 'unknown option' [ $? = 2 ]

printf '%d checks passed, %d failed\n' "$passed" "$failed"
((failed == 0))
