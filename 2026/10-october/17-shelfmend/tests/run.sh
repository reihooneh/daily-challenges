#!/usr/bin/env bash
# Tests for Shelfmend. Run with:  bash tests/run.sh
# shellcheck source-path=SCRIPTDIR
# Single-quoted $(...) is deliberate (attack strings), and "a && fail || pass" is safe here
# because fail and pass always succeed.
# shellcheck disable=SC2015,SC2016
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin/shelfmend"
source "$HERE/../lib/callnumber.sh"
source "$HERE/../lib/lis.sh"

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); echo "FAIL  $1"; }
same() { if [[ $2 == "$3" ]]; then pass; else fail "$1: expected '$2', got '$3'"; fi; }
contains() { if [[ $3 == *"$2"* ]]; then pass; else fail "$1: missing '$2' in: ${3:0:300}"; fi; }

before() { # before A B: call number A must shelve before B
  local a b
  callnumber_key "$1" || { fail "can't read '$1': $WHY"; return; }
  a=$KEY
  callnumber_key "$2" || { fail "can't read '$2': $WHY"; return; }
  b=$KEY
  if [[ $a < $b ]]; then pass; else fail "'$1' should come before '$2'"; fi
}
unreadable() {
  if callnumber_key "$1" "${2:-auto}"; then fail "should not read '$1'"; else pass; fi
}

# ---------- 1. Call number order ----------
before 'Q76' 'QA76'
before 'QA76' 'QA76.5'
before 'QA76.5' 'QA76.73'
before 'QA76.73' 'QA77'
before 'QA9' 'QA76'                  # class numbers are whole numbers: 9 < 76
before 'QA76.73' 'QA76.9'            # but the decimal part is a decimal: .73 < .9
before 'QA76.73 .P98' 'QA76.73 .P983'  # cutters are decimals too
before 'QA76.73 .P983' 'QA76.73 .P99'
before 'QA76.73 .P98' 'QA76.73 .P98 S65'  # nothing before something
before 'QA76.73 .P98 S65' 'QA76.73 .P98 2019' # a cutter before a year
before 'QA76.73 .P98 2019' 'QA76.73 .P98 2019 v.1'
before 'QA76.6 .K64 1997 v.2' 'QA76.6 .K64 1997 v.10' # volumes are numbers
before 'PS3545 .I345 Z5 1989' 'PS3545 .I345 Z5 1989 c.2'
before 'PS3545.I345' 'PS3545 .I35'
before '823' '823.1'
before '823.1' '823.914 ROW'
before '823.914 ROW' '823.914 RUS'
before '005.133 LUT' '823.914 ROW'
callnumber_key 'qa76.73 .p98 v. 2' && same 'lower case and "v. 2" are normalised' "$KEY" "$(callnumber_key 'QA76.73 .P98 v.2'; echo "$KEY")"
callnumber_key 'QA76.73.P98' && same 'cutter written without a space' "$KEY" "$(callnumber_key 'QA76.73 .P98'; echo "$KEY")"
callnumber_key '823.914 ROW' lc && fail 'Dewey refused when lc is asked for' || pass
callnumber_key 'QA76' dewey && fail 'LC refused when dewey is asked for' || pass

unreadable 'QA76 .X'
unreadable 'hello world'
unreadable 'QA76.73 .P98 <script>'
unreadable 'a[$(touch /tmp/shelfmend-pwned)]'
unreadable '9999999'
unreadable 'QA123456'

# ---------- 2. The fewest moves ----------
keys=(a b c d e)
lis_keep keys
same 'in order: nothing moves' 5 "$KEPT"
keys=(e d c b a)
lis_keep keys
same 'reversed: only one stays' 1 "$KEPT"
keys=(a b z c d e)
lis_keep keys
same 'one book out of place' '1 1 0 1 1 1' "${KEEP[*]}"
keys=(a b b b c)
lis_keep keys
same 'copies of the same book can stand together' 5 "$KEPT"

# Brute force: the longest in-order run, by checking every subset, on random small shelves.
brute() {
  local -n arr=$1
  local n=${#arr[@]} mask best=0 i last cnt ok
  for ((mask = 0; mask < (1 << n); mask++)); do
    last='' cnt=0 ok=1
    for ((i = 0; i < n; i++)); do
      ((mask >> i & 1)) || continue
      if [[ -n $last && ${arr[i]} < $last ]]; then ok=0; break; fi
      last=${arr[i]}
      cnt=$((cnt + 1))
    done
    ((ok && cnt > best)) && best=$cnt
  done
  echo "$best"
}
RANDOM=17
bad=0
for ((t = 0; t < 120; t++)); do
  keys=()
  for ((i = 0; i < RANDOM % 8 + 1; i++)); do keys+=("k$((RANDOM % 6))"); done
  lis_keep keys
  # What stays must be in order...
  last=''
  for ((i = 0; i < ${#keys[@]}; i++)); do
    ((KEEP[i])) || continue
    [[ -n $last && ${keys[i]} < $last ]] && bad=1
    last=${keys[i]}
  done
  # ...and no bigger set could stay.
  [[ $(brute keys) == "$KEPT" ]] || bad=1
  ((bad)) && { fail "random shelf ${keys[*]}"; break; }
done
((bad)) || pass

# ---------- 3. The command line ----------
out=$("$BIN" "$HERE/../examples/qa76.txt")
code=$?
same 'example needs moves (exit 1)' 1 "$code"
contains 'move count' 'Move 4 books' "$out"
contains 'book-by-book check is misled' 'flags 4 books, and 2 of them are' "$out"
contains 'misplaced database book goes after its neighbour' 'after position 17: QA76.9 .D3 D3726 2004' "$out"
contains 'two volumes go to the same gap, in order' 'at the start: QA76.6 .K64 1997 v.1, QA76.6 .K64 1997 v.3' "$out"

out=$(printf 'QA1\nQA2 | ok\n' | "$BIN" -)
same 'in-order shelf exits 0' 0 "$?"
contains 'reads standard input' 'standard input' "$out"

out=$(printf 'QA2\nQA1 | $(touch /tmp/shelfmend-pwned) `id`\n' | "$BIN" -)
contains 'titles are printed as text' '$(touch /tmp/shelfmend-pwned) `id`' "$out"
[[ -e /tmp/shelfmend-pwned ]] && fail 'input ran a command' || pass

err=$(printf 'QA1\nQA2 .P9 \e[31m\n' | "$BIN" - 2>&1)
same 'terminal escapes are refused' 2 "$?"
[[ $err == *$'\e'* ]] && fail 'error repeats the escape code' || pass
err=$(printf 'QA1 | \xe2\x80\xae evil\n' | "$BIN" - 2>&1)
contains 'hidden direction marks are refused' 'hidden direction' "$err"
err=$(printf 'QA1 .X\nnonsense\n' | "$BIN" - 2>&1)
contains 'unreadable lines are listed with line numbers' "line 2: not a Library of Congress or Dewey" "$err"
err=$(printf "QA1 | %0200d\n" 0 | "$BIN" - 2>&1)
contains 'long lines are refused' 'longer than' "$err"
err=$(head -c 1100000 /dev/zero | tr '\0' 'Q' | "$BIN" - 2>&1)
contains 'big input is refused' 'larger than 1 MB' "$err"
err=$("$BIN" /dev/zero 2>&1)
same '/dev/zero is refused' 2 "$?"
tmp=$(mktemp -d)
ln -s "$HERE/../examples/qa76.txt" "$tmp/link.txt"
err=$("$BIN" "$tmp/link.txt" 2>&1)
same 'symlinks are refused' 2 "$?"
printf 'QA1\n' >"$tmp/$(printf 'bad\033[31mname.txt')"
out=$("$BIN" "$tmp/"bad*name.txt 2>&1)
[[ $out == *$'\e'* ]] && fail 'file name escape printed' || pass
rm -rf "$tmp"
err=$("$BIN" --rm 2>&1)
same 'unknown option exits 2' 2 "$?"
err=$("$BIN" a b 2>&1)
same 'two files exit 2' 2 "$?"
err=$("$BIN" --scheme pinyin x 2>&1)
same 'bad scheme exits 2' 2 "$?"
out=$(printf '823.914 ROW\nQA76\n' | "$BIN" -)
contains 'mixed schemes are reported' 'mixed: 1 Library of Congress, 1 Dewey' "$out"
err=$(printf 'QA76\n' | "$BIN" --scheme dewey - 2>&1)
same 'forced scheme is enforced' 2 "$?"

# Big shelf: 5,000 books with 50 misplaced, in reasonable time.
big=$(for ((i = 0; i < 5000; i++)); do
  if ((i % 100 == 50)); then printf 'QA%d\n' $((i + 300)); else printf 'QA%d\n' $((i + 1)); fi
done)
start=$SECONDS
out=$(printf '%s\n' "$big" | "$BIN" -)
contains 'big shelf: one move per misplaced book' 'Move 50 books' "$out"
((SECONDS - start < 60)) && pass || fail 'big shelf too slow'

echo
echo "$passed passed, $failed failed"
((failed == 0))
