#!/usr/bin/env bash
# Tests for Last Digit. Run with:  bash tests/run.sh
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin/lastdigit"
# shellcheck source=lib/schemes.sh
source "$HERE/../lib/schemes.sh"

passed=0
failed=0

ok() { # ok DESCRIPTION COMMAND...   passes when the command succeeds
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then passed=$((passed + 1)); else
    failed=$((failed + 1))
    echo "FAIL  $what"
  fi
}

not_ok() {
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then
    failed=$((failed + 1))
    echo "FAIL  $what"
  else passed=$((passed + 1)); fi
}

same() { # same DESCRIPTION EXPECTED ACTUAL
  if [[ $2 == "$3" ]]; then passed=$((passed + 1)); else
    failed=$((failed + 1))
    echo "FAIL  $1: expected '$2', got '$3'"
  fi
}

contains() { # contains DESCRIPTION NEEDLE HAYSTACK
  if [[ $3 == *"$2"* ]]; then passed=$((passed + 1)); else
    failed=$((failed + 1))
    echo "FAIL  $1: '$2' not found"
  fi
}

# ---- published examples of each kind ------------------------------------------
# Well-known documentation and test values, not anyone's real details.

declare -A GOOD=(
  [gtin]="9780306406157 4006381333931 036000291452 73513537 10012345678902"
  [isbn10]="0306406152 080442957X 0198526636"
  [issn]="03785955 20493630 2434561X"
  [card]="4111111111111111 5555555555554444 378282246310005 4012888888881881"
  [imei]="490154203237518"
  [abn]="51824753556 53004085616"
  [acn]="004085616 000000019 010499966"
  [tfn]="123456782"
  [medicare]="2123456701 3950000051 39500000511"
  [iban]="GB82WEST12345698765432 DE89370400440532013000 FR1420041010050500013M02606 NL91ABNA0417164300"
)

for id in "${SCHEMES[@]}"; do
  for number in ${GOOD[$id]}; do
    ok "$id accepts $number" "fits_$id" "$number"
    ok "$id validates $number" "valid_$id" "$number"
  done
done
same "every scheme has examples" "${#SCHEMES[@]}" "${#GOOD[@]}"
same "every scheme has a name" "${#SCHEMES[@]}" "${#SCHEME_NAME[@]}"

# ---- the expected check digit is the real one ----------------------------------

for id in gtin isbn10 issn card imei acn tfn; do
  for number in ${GOOD[$id]}; do
    same "$id expected digit for $number" "${number: -1}" "$("expected_$id" "$number")"
  done
done
same "medicare ninth digit" "0" "$(expected_medicare 2123456701)"
same "IBAN check digits" "82" "$(expected_iban GB00WEST12345698765432)"
same "IBAN check digits of a second published example" "29" "$(expected_iban GB00NWBK60161331926819)"
padded=""
for account in {100..400}; do # find an account whose check digits start with 0
  digits=$(expected_iban "GB00WEST12345698765$account")
  if [[ $digits == 0? ]]; then
    padded=$digits
    break
  fi
done
ok "IBAN check digits below 10 keep their leading zero" test "${#padded}" -eq 2
same "card networks" "Visa|Mastercard|Mastercard|American Express|not one this tool recognises" \
  "$(card_network 4111111111111111)|$(card_network 5555555555554444)|$(card_network 2221000000000009)|$(card_network 378282246310005)|$(card_network 6011111111111117)"

# ---- error detection: what each scheme is FOR ----------------------------------

# Change every digit of a number to every other value. Returns how many changes went unnoticed.
undetected_substitutions() {
  local id=$1 n=$2 i d missed=0 changed
  for ((i = 0; i < ${#n}; i++)); do
    [[ ${n:i:1} == [0-9] ]] || continue
    for d in 0 1 2 3 4 5 6 7 8 9; do
      [[ $d == "${n:i:1}" ]] && continue
      changed=${n:0:i}$d${n:i+1}
      if "fits_$id" "$changed" && "valid_$id" "$changed"; then missed=$((missed + 1)); fi
    done
  done
  echo "$missed"
}

undetected_swaps() {
  local id=$1 n=$2 i missed=0 swapped
  for ((i = 0; i < ${#n} - 1; i++)); do
    [[ ${n:i:1} == "${n:i+1:1}" ]] && continue
    swapped=${n:0:i}${n:i+1:1}${n:i:1}${n:i+2}
    if "fits_$id" "$swapped" && "valid_$id" "$swapped"; then missed=$((missed + 1)); fi
  done
  echo "$missed"
}

same "a barcode catches every single wrong digit" 0 "$(undetected_substitutions gtin 9780306406157)"
same "Luhn catches every single wrong digit" 0 "$(undetected_substitutions card 4012888888881881)"
same "ISBN-10 catches every single wrong digit" 0 "$(undetected_substitutions isbn10 0306406152)"
same "ISBN-10 catches every swap of neighbours" 0 "$(undetected_swaps isbn10 0306406152)"
same "ISSN catches every single wrong digit" 0 "$(undetected_substitutions issn 03785955)"
same "a TFN catches every single wrong digit" 0 "$(undetected_substitutions tfn 123456782)"
same "an ABN catches every single wrong digit" 0 "$(undetected_substitutions abn 51824753556)"
same "an IBAN catches every single wrong digit" 0 "$(undetected_substitutions iban GB82WEST12345698765432)"
same "an IBAN catches every swap of neighbours" 0 "$(undetected_swaps iban GB82WEST12345698765432)"
# Known weakness, kept as a test so the README's claim stays honest:
ok "Luhn misses the 09 <-> 90 swap" test "$(undetected_swaps card 4000000000000903)" -ge 1
ok "a barcode misses swaps of digits that differ by 5 (1 <-> 6)" test "$(undetected_swaps gtin 9780306406157)" -ge 1

# ---- shapes ---------------------------------------------------------------------

not_ok "letters are not a barcode" fits_gtin 97803064061AB
not_ok "an ISBN-10 X can only be last" fits_isbn10 03064X6152
not_ok "an ABN cannot start with 0" fits_abn 01824753556
not_ok "a Medicare number starts with 2 to 6" fits_medicare 9123456701
not_ok "an IBAN needs two letters first" fits_iban 8282WEST12345698765432
not_ok "an IBAN that is too long" fits_iban "GB82$(printf 'A%.0s' {1..31})"
same "mod 97 of a 60-digit number" "1" "$(mod97 "WEST12345698765432GB82")"
same "mod 97 handles leading zeros" "$((1234 % 97))" "$(mod97 0000001234)"

# ---- the command line -------------------------------------------------------------

run() { # sets CODE, OUT, ERR
  local out_file err_file
  out_file=$(mktemp) err_file=$(mktemp)
  "$BIN" "$@" >"$out_file" 2>"$err_file"
  CODE=$?
  OUT=$(<"$out_file") ERR=$(<"$err_file")
  rm -f -- "$out_file" "$err_file"
}

run 978-0-306-40615-7
same "valid number exits 0" 0 "$CODE"
contains "names the kind" "VALID    Barcode (EAN / UPC / ISBN-13)" "$OUT"
contains "shows the working" "= 93" "$OUT"
contains "warns what validity does not mean" "does not mean the number exists" "$OUT"

run "9780 3064 0651 7"
same "invalid number exits 1" 1 "$CODE"
contains "says which digit is wrong" "its last digit should be 5, not 7" "$OUT"
contains "suggests the swap that fixes it" "9780306406157 would be valid" "$OUT"

run 12345
same "unknown shape exits 1" 1 "$CODE"
contains "explains unknown shapes" "No kind of number this tool knows" "$OUT"

run gb82 west 1234 5698 7654 32
same "several arguments are refused" 2 "$CODE"
run "gb82 west 1234 5698 7654 32"
same "lower-case IBAN with spaces" 0 "$CODE"

run --quiet 4111111111111111
same "--quiet exits 0" 0 "$CODE"
not_ok "--quiet hides the arithmetic" grep -q "double every second" <<<"$OUT"

run --list
same "--list prints every kind" "${#SCHEMES[@]}" "$(wc -l <<<"$OUT" | tr -d ' ')"

OUT=$(printf '4111111111111111\n' | "$BIN" - 2>/dev/null)
contains "hidden mode masks the middle of the number" "41************11" "$OUT"
not_ok "hidden mode never prints the full number" grep -q 4111111111111111 <<<"$OUT"
not_ok "hidden mode prints no arithmetic" grep -q " + " <<<"$OUT"

# ---- hostile input ---------------------------------------------------------------

marker="$HERE/../hacked-$$"
# shellcheck disable=SC2016  # the point is that these are NOT expanded
hostile=(
  '$(touch '"$marker"')' '`touch '"$marker"'`' '; touch '"$marker" '| touch '"$marker" '1234 > '"$marker"
  '<script>alert(1)</script>' '../../etc/passwd' '%s%n%x' '--' 'a[$(touch '"$marker"')]' 'x=1' '*' '?' '~'
  $'4111\n1111' $'\e[2J\e]0;owned\a' $'12\t34' '１２３４５６７８' '4111_1111' '4111.1111' '+61 400 000 000'
)
for attack in "${hostile[@]}"; do
  run "$attack"
  same "hostile input is refused: $(printf '%q' "$attack")" 2 "$CODE"
  same "nothing on standard output" "" "$OUT"
  ok "one clean line on standard error" test "$(wc -l <<<"$ERR")" -eq 1
  not_ok "the message does not repeat the input" grep -qE 'owned|script|passwd|touch' <<<"$ERR"
done
not_ok "no hostile input was ever executed" test -e "$marker"

run "$(printf '1%.0s' {1..41})"
same "over-long input is refused" 2 "$CODE"
contains "with a reason" "longer than 40 characters" "$ERR"
run ""
same "empty input is refused" 2 "$CODE"
run 7
same "a single digit is refused" 2 "$CODE"
run
same "no arguments exits 2" 2 "$CODE"
run --help
same "--help exits 0" 0 "$CODE"

CODE=0
head -c 5000000 /dev/zero | tr '\0' '9' | "$BIN" - >/dev/null 2>&1 || CODE=$?
same "an endless stream on standard input is cut off, not swallowed" 2 "$CODE"

# The 34-character maximum for an IBAN must not overflow the arithmetic.
same "longest possible input stays exact" "$(mod97 "$(printf '9%.0s' {1..34})")" "$(python3 -c 'print(int("9"*34) % 97)' 2>/dev/null || mod97 "$(printf '9%.0s' {1..34})")"

if command -v shellcheck >/dev/null 2>&1; then
  ok "shellcheck finds nothing" shellcheck -x "$BIN" "$HERE/../lib/schemes.sh" "$HERE/run.sh"
fi

echo "$passed passed, $failed failed"
((failed == 0))
