#!/usr/bin/env bash
# Tests for Dawnlist: hand-worked days, the pruned search against the unpruned one on random days,
# the example, and hostile files.
set -euo pipefail
export LC_ALL=C

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT="$HERE/.."
BIN="$ROOT/bin/dawnlist"
AWK="$ROOT/lib/dawnlist.awk"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }

# Runs the planner on text and prints "expected route complete".
plan() { printf '%s\n' "$1" | awk -v machine=1 -v exact="${2:-0}" -f "$AWK"; }

expect_plan() { # name text want_expected want_route
  local got
  got=$(plan "$2")
  if [[ $(awk -v a="${got%% *}" -v b="$3" 'BEGIN { print (a - b < 1e-6 && b - a < 1e-6) }') == 1 ]] &&
    [[ $(cut -d' ' -f2 <<<"$got") == "$4" ]]; then ok; else bad "$1: got '$got', want $3 $4"; fi
}

# ---------------------------------------------------------------- hand-worked days
two='start home 05:00
end 08:00
site a 30 A
site b 30 B
travel home a 10
travel home b 10
travel a b 10
bird a 0.5 Robin
bird b 0.5 Robin'
expect_plan 'two halves make three quarters' "$two" 0.75 'a@05:10,b@05:50'

wait='start home 05:00
end 08:00
site a 30 A
travel home a 10
bird a 1 06:00-07:00 Owl
bird a 0.2 Owl'
expect_plan 'waits for the window to open' "$wait" 1 'a@06:00'

tight='start home 05:00
end 06:00
site a 45 A
site b 45 B
travel home a 10
travel home b 10
travel a b 5
bird a 0.9 Wren
bird b 0.5 Wren
bird b 0.5 Finch'
expect_plan 'only one site fits; the richer one wins' "$tight" 1 'b@05:10'

never='start home 05:00
end 06:00
site a 45 A
travel home a 30
bird a 0.9 Wren'
expect_plan 'nothing reachable in time' "$never" 0 '-'

# ---------------------------------------------------------------- random days: pruning loses nothing
RANDOM=26
for trial in $(seq 1 40); do
  n=$((2 + RANDOM % 5))
  text="start home 05:00
end $(printf '%02d' $((8 + RANDOM % 5))):00"
  for ((i = 1; i <= n; i++)); do text+=$'\n'"site s$i $((20 + RANDOM % 60)) Site $i"; done
  for ((i = 0; i <= n; i++)); do
    for ((j = i + 1; j <= n; j++)); do
      ((RANDOM % 6 == 0)) && continue # some places have no road between them
      a=s$i; ((i == 0)) && a=home
      text+=$'\n'"travel $a s$j $((5 + RANDOM % 50))"
    done
  done
  for ((i = 1; i <= n; i++)); do
    for sp in 1 2 3 4 5 6; do
      ((RANDOM % 2)) || continue
      text+=$'\n'"bird s$i 0.$((1 + RANDOM % 9)) Bird $sp"
      ((RANDOM % 3)) || text+=$'\n'"bird s$i 0.9$((RANDOM % 9)) $(printf '%02d' $((5 + RANDOM % 5))):00-$(printf '%02d' $((10 + RANDOM % 3))):00 Bird $sp"
    done
  done
  text+=$'\n'"bird s1 0.5 Bird 1"
  pruned=$(plan "$text" 0)
  full=$(plan "$text" 1)
  if [[ $(awk -v a="${pruned%% *}" -v b="${full%% *}" 'BEGIN { print (a - b < 1e-6 && b - a < 1e-6) }') == 1 ]]; then ok; else
    bad "trial $trial: pruned $pruned, full $full"
  fi
done

# ---------------------------------------------------------------- the example and the command line
out=$("$BIN" "$ROOT/examples/spring-day.txt")
if grep -q 'Expected species: 20.6 of 44 (the best possible order' <<<"$out"; then ok; else bad 'example expected species'; fi
if grep -q '05:15-06:05  Reedy lagoon' <<<"$out"; then ok; else bad 'example starts at the lagoon'; fi
if tr '\n' ' ' <<<"$out" | grep -q 'No chance on this route.*Southern Boobook'; then ok; else bad 'example: a dusk owl is out of reach before midday'; fi
if [[ $("$BIN" - <"$ROOT/examples/spring-day.txt") == "$out" ]]; then ok; else bad 'standard input'; fi
if "$BIN" --budget 1000 "$ROOT/examples/spring-day.txt" | grep -q 'search stopped at its limit'; then ok; else bad 'budget reported'; fi

# ---------------------------------------------------------------- hostile input
rejects() { # name text
  if printf '%s\n' "$2" >"$TMP/day.txt" && ! "$BIN" "$TMP/day.txt" >/dev/null 2>"$TMP/err"; then
    if grep -q $'\e' "$TMP/err"; then bad "$1: escape code echoed"; else ok; fi
  else bad "$1: accepted"; fi
}
base=$'start home 05:00\nend 09:00\nsite a 30 A\ntravel home a 10\nbird a 0.5 Wren'
rejects 'terminal escape' "${base/Wren/$'Wren\e[2J'}"
rejects 'unknown line' "$base"$'\nrm -rf /'
rejects 'command substitution is just text' "${base/Wren/\$(reboot)}"
rejects 'chance above one' "${base/0.5/1.5}"
rejects 'chance of zero' "${base/0.5/0.0}"
rejects 'exponent' "${base/0.5/5e-1}"
rejects 'negative minutes' "${base/a 30/a -30}"
rejects 'huge minutes' "${base/a 30/a 99999}"
rejects 'bad clock' "${base/05:00/25:00}"
rejects 'backwards window' "${base/0.5/0.5 08:00-06:00}"
rejects 'duplicate site' "$base"$'\nsite a 20 Again'
rejects 'travel to nowhere' "$base"$'\ntravel a nowhere 5'
rejects 'start is a site' "${base/start home/start a}"
rejects 'no end' "${base/end 09:00/}"
rejects 'day ends before it starts' "${base/end 09:00/end 04:00}"
rejects 'long line' "$base"$'\n# '"$(printf 'x%.0s' $(seq 1 250))"
many=$base
for i in $(seq 1 12); do many+=$'\n'"site x$i 10 X"; done
rejects 'thirteen sites' "$many"
head -c 70000 /dev/zero | tr '\0' '#' >"$TMP/big.txt"
if "$BIN" "$TMP/big.txt" >/dev/null 2>&1; then bad 'oversize file accepted'; else ok; fi
ln -s "$ROOT/examples/spring-day.txt" "$TMP/link.txt"
if "$BIN" "$TMP/link.txt" >/dev/null 2>&1; then bad 'symlink accepted'; else ok; fi
if "$BIN" "$TMP" >/dev/null 2>&1; then bad 'directory accepted'; else ok; fi
if "$BIN" --budget 5 "$ROOT/examples/spring-day.txt" >/dev/null 2>&1; then bad 'tiny budget accepted'; else ok; fi
if "$BIN" --budget '1;id' "$ROOT/examples/spring-day.txt" >/dev/null 2>&1; then bad 'odd budget accepted'; else ok; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
