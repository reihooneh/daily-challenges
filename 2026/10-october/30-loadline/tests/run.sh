#!/usr/bin/env bash
# Tests for Loadline. Run from anywhere:  bash tests/run.sh
# The checks pass code to "bash -c" in single quotes on purpose (SC2016), and colour pairs are
# split into words on purpose (SC2086).
# shellcheck disable=SC2016,SC2086
set -uo pipefail
export LC_ALL=C

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin/loadline"
passed=0 failed=0

check() { # description, then a command that must succeed
  local what=$1; shift
  if "$@"; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  %s\n' "$what"; fi
}

# Runs loadline on text given as an argument; sets OUT, ERR and CODE.
run() {
  local errf
  errf=$(mktemp)
  OUT=$(printf '%s' "$1" | "$BIN" - 2>"$errf")
  CODE=$?
  ERR=$(<"$errf")
  rm -f -- "$errf"
}
has() { [[ $OUT == *"$1"* ]]; }
err_has() { [[ $ERR == *"$1"* ]]; }
loads() { local n; n=$(grep -c '^Load [0-9]*:' <<<"$OUT"); [[ $n == "$1" ]]; }

M=$'machine 7 kg\n'

# ---------- Packing ----------
run "${M}item Shirts x 5 0.25 kg cotton white 40"$'\n'
check 'one small item: one load' loads 1
check 'and it is proven the fewest' has 'the fewest possible'
check 'cotton at the label temperature' has 'cotton programme at 40 C'

run "${M}item Shirts x 5 0.25 kg cotton white 40"$'\n'"item Jeans x 2 0.7 kg cotton dark 40"$'\n'
check 'whites and darks wash apart' loads 2

run "${M}item New red top x 1 0.3 kg cotton red 40 bleeds"$'\n'"item Red socks x 4 0.05 kg cotton red 40"$'\n'
check 'a bleeding red goes with other reds' loads 1
run "${M}item New red top x 1 0.3 kg cotton red 40 bleeds"$'\n'"item Black tee x 2 0.2 kg cotton dark 40"$'\n'
check 'but not with darks it could run into' loads 2
check 'and the plan says why' has 'may bleed: only red with it'

run "${M}item Jumpers x 8 0.25 kg wool dark 30"$'\n'
check 'a wool programme takes a quarter of the drum: 2 kg of wool needs two loads' loads 2
check 'split evenly, four and four' bash -c '[[ $(grep -c "4 x Jumpers" <<<"$1") == 2 ]]' _ "$OUT"
check 'and the wool programme is named' has 'wool programme at 30 C, 1.0 of 1.8 kg'

run "${M}item Towels x 2 0.6 kg cotton white 60 hot"$'\n'"item Sports top x 1 0.2 kg synthetic white 40"$'\n'
check 'mixed fabrics take the gentler programme and lower temperature' has 'synthetic programme at 40 C'
check 'and the towels are flagged as wanting 60' has '(wanted 60 C)'

run "${M}item Towels x 2 0.6 kg cotton white 60 hot"$'\n'"item Sheets x 2 0.7 kg cotton light 60 hot"$'\n'
check 'hot whites and lights share a 60 C cotton load' has 'cotton programme at 60 C'
check 'with no complaint' bash -c '[[ $1 != *"wanted 60"* ]]' _ "$OUT"

run "${M}item King duvet x 1 9 kg cotton white 60"$'\n'"item Shirt x 1 0.25 kg cotton white 40"$'\n'
check 'an item heavier than the drum is sent elsewhere' has 'too heavy for a cotton programme'
check 'and the rest is still planned' loads 1

run "machine 5 kg"$'\n'"item Towels x 12 0.6 kg cotton white 60 hot"$'\n'
check 'a big item is split into as few loads as its weight needs (7.2 kg in a 5 kg drum: 2)' loads 2

# Colour rules are symmetric and whites never meet darks or reds.
for pair in 'white dark' 'white red' 'white bright' 'light dark' 'light red' 'bright red'; do
  set -- $pair
  run "${M}item A x 1 0.3 kg cotton $1 40"$'\n'"item B x 1 0.3 kg cotton $2 40"$'\n'
  check "$1 and $2 wash apart" loads 2
  run "${M}item A x 1 0.3 kg cotton $2 40"$'\n'"item B x 1 0.3 kg cotton $1 40"$'\n'
  check "$2 and $1 wash apart" loads 2
done
for pair in 'white light' 'light bright' 'bright dark' 'dark red'; do
  set -- $pair
  run "${M}item A x 1 0.3 kg cotton $1 40"$'\n'"item B x 1 0.3 kg cotton $2 40"$'\n'
  check "$1 and $2 may share" loads 1
done

# The worked example: five loads, proven.
OUT=$("$BIN" "$HERE/../examples/saturday.txt"); CODE=$?
check 'the example runs' test "$CODE" -eq 0
check 'in five proven loads' has '12.2 kg in 5 loads: the fewest possible'
check 'the bleeding hoodie is alone' bash -c 'grep -A2 "^Load 5" <<<"$1" | grep -q "New red hoodie" && [[ $(grep -A2 "^Load 5" <<<"$1" | grep -c " x ") == 1 ]]' _ "$OUT"
EX=$OUT
OUT=$("$BIN" - <"$HERE/../examples/saturday.txt")
check 'standard input gives the same plan' test "$OUT" == "$EX"

# A big basket: too many items for the exact check, so the bound is shown instead.
big="machine 8 kg"$'\n'
for i in $(seq 1 25); do
  c=$(((i % 3) == 0 ? 1 : 2)); col=(white light bright dark red); f=(cotton synthetic cotton cotton synthetic)
  big+="item Item $i x $c 0.$((i % 9 + 1)) kg ${f[i % 5]} ${col[i % 5]} 40"$'\n'
done
run "$big"
check 'a big basket is planned' test "$CODE" -eq 0
check 'with the lower bound stated' has 'No plan can use fewer than'
# Every load respects its capacity: weight never above the programme's limit.
check 'no load is over its capacity' bash -c 'awk "/^Load/ { split(\$0, a, \", \"); split(a[2], b, \" \"); if (b[1] + 0 > b[3] + 0.0001) bad = 1 } END { exit bad }" <<<"$1"' _ "$OUT"

# ---------- The file ----------
rejects() { # text, expected part of the message
  run "$1"
  check "rejects: $2 (got: $ERR)" bash -c '[[ $0 == 2 && $1 == *"$2"* ]]' "$CODE" "$ERR" "$2"
  check "never echoes the input ($2)" bash -c '[[ $0 != *"<"* ]]' "$ERR"
}
rejects "item A x 1 0.3 kg cotton white 40"$'\n' "needs a 'machine' line"
rejects "$M" 'has no items'
rejects "machine 30 kg"$'\n' '3 to 20 kg'
rejects "machine seven"$'\n' "'machine 7 kg'"
rejects "${M}${M}" "comes once"
rejects "${M}item A x 1 0.3 kg linen white 40"$'\n' 'write items like'
rejects "${M}item A x 1 0.3 kg cotton purple 40"$'\n' 'write items like'
rejects "${M}item A x 1 0.3 kg cotton white 50"$'\n' 'write items like'
rejects "${M}item A x 1 1e1 kg cotton white 40"$'\n' 'write items like'
rejects "${M}item A x 0 0.3 kg cotton white 40"$'\n' 'at least 1'
rejects "${M}item A x 1 0.01 kg cotton white 40"$'\n' '0.05 to 10 kg'
rejects "${M}item A x 1 0.3 kg cotton white 40 hot"$'\n' "'hot' needs"
rejects "${M}item <script> x 1 0.3 kg cotton white 40"$'\n' 'names use letters'
rejects "${M}item \$(reboot) x 1 0.3 kg cotton white 40"$'\n' 'names use letters'
rejects "${M}dry everything"$'\n' 'lines start with'
rejects "${M}item A"$'\e'"[2J x 1 0.3 kg cotton white 40"$'\n' 'control character'
rejects "${M}item Caf"$'\xc3\xa9'" x 1 0.3 kg cotton white 40"$'\n' 'plain ASCII'
rejects "${M}# $(printf '%0300d' 0)"$'\n' 'longer than 200'
rejects "$(printf '%040000d' 0)" 'larger than 32 KB'
many="$M"; for i in $(seq 1 61); do many+="item I$i x 1 0.1 kg cotton white 40"$'\n'; done
rejects "$many" 'at most 60 items'
lots="$M"; for i in $(seq 1 3); do lots+="item I$i x 90 0.1 kg cotton white 40"$'\n'; done
rejects "$lots" 'at most 200 pieces'
run $'\xef\xbb\xbf'"${M}item A x 1 0.3 kg cotton white 40"$'\n'
check 'a byte-order mark is skipped' test "$CODE" -eq 0

# ---------- The command line ----------
"$BIN" >/dev/null 2>&1; check 'no arguments: exit 2' test $? -eq 2
"$BIN" a b >/dev/null 2>&1; check 'two arguments: exit 2' test $? -eq 2
ERR=$("$BIN" "$HERE" 2>&1 >/dev/null); check 'a folder is refused' bash -c '[[ $1 == *"could not be read"* ]]' _ "$ERR"
ERR=$("$BIN" secret-name-zz.txt 2>&1 >/dev/null); check "errors don't echo the path" bash -c '[[ $1 != *secret-name* ]]' _ "$ERR"
ERR=$("$BIN" '-; rm -rf /' 2>&1 >/dev/null); check 'a path that looks like a command is just a missing file' bash -c '[[ $1 == *"could not be read"* ]]' _ "$ERR"
OUT=$(head -c 100000 /dev/zero | tr '\0' '#' | "$BIN" - 2>&1); check 'an endless stream is cut off' has 'larger than 32 KB'
if command -v shellcheck >/dev/null; then
  check 'shellcheck finds nothing' shellcheck "$BIN"
fi

printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
