# shellcheck shell=bash
# Check-digit schemes. Each scheme has up to four functions:
#
#   fits_<id> NUMBER      does the number have the right shape to be one?
#   valid_<id> NUMBER     does its check digit agree?
#   expected_<id> NUMBER  print the check character it SHOULD have
#   explain_<id> NUMBER   print the arithmetic, one step per line
#
# NUMBER is always already normalised: upper case, digits and letters only.
# Nothing here uses eval, and no input is ever used as a command or a pattern.

# shellcheck disable=SC2034  # used by bin/lastdigit, which sources this file
SCHEMES=(gtin isbn10 issn card imei abn acn tfn medicare iban)

# shellcheck disable=SC2034
declare -A SCHEME_NAME=(
  [gtin]="Barcode (EAN / UPC / ISBN-13)"
  [isbn10]="ISBN-10 (older books)"
  [issn]="ISSN (journals and magazines)"
  [card]="Payment card"
  [imei]="IMEI (phone serial number)"
  [abn]="Australian Business Number"
  [acn]="Australian Company Number"
  [tfn]="Australian Tax File Number"
  [medicare]="Australian Medicare card"
  [iban]="IBAN (international bank account)"
)

is_digits() { [[ $1 =~ ^[0-9]+$ ]]; }

# weighted_sum DIGITS W1 W2 ...  -> prints the sum of digit x weight.
# With a second output variable name it also builds "4x1 + 1x3 + ..." text.
weighted_sum() {
  local digits=$1 sum=0 i text=""
  shift
  for ((i = 0; i < ${#digits} && i < $#; i++)); do
    local w=${*:i+1:1}
    sum=$((sum + ${digits:i:1} * w))
    text+="${text:+ + }${digits:i:1}x${w}"
  done
  WORKING=$text
  printf '%s' "$sum"
}

# ---- barcodes: EAN-8, UPC-A, EAN-13 / ISBN-13, GTIN-14 -----------------------
# Weights 3,1,3,1... counted from the digit next to the check digit.

fits_gtin() { is_digits "$1" && [[ ${#1} == 8 || ${#1} == 12 || ${#1} == 13 || ${#1} == 14 ]]; }

gtin_weights() {
  local n=$1 i out=()
  for ((i = 0; i < n; i++)); do
    if (((n - i) % 2 == 1)); then out+=(3); else out+=(1); fi
  done
  printf '%s ' "${out[@]}"
}

expected_gtin() {
  local body=${1:0:${#1}-1} sum
  # shellcheck disable=SC2046  # the weights are meant to become separate arguments
  sum=$(weighted_sum "$body" $(gtin_weights ${#body}))
  printf '%s' $(((10 - sum % 10) % 10))
}

valid_gtin() { [[ $(expected_gtin "$1") == "${1: -1}" ]]; }

explain_gtin() {
  local body=${1:0:${#1}-1} sum
  # shellcheck disable=SC2046
  weighted_sum "$body" $(gtin_weights ${#body}) >/dev/null
  # shellcheck disable=SC2046
  sum=$(weighted_sum "$body" $(gtin_weights ${#body}))
  echo "Multiply the digits by 3 and 1 in turn, starting with 3 next to the check digit:"
  echo "$WORKING = $sum"
  echo "The check digit tops the sum up to a multiple of 10: (10 - $((sum % 10))) mod 10 = $(((10 - sum % 10) % 10))"
}

# ---- ISBN-10: weights 10..2, modulo 11, where "X" means 10 --------------------

fits_isbn10() { [[ $1 =~ ^[0-9]{9}[0-9X]$ ]]; }

expected_isbn10() {
  local sum check
  sum=$(weighted_sum "${1:0:9}" 10 9 8 7 6 5 4 3 2)
  check=$(((11 - sum % 11) % 11))
  if ((check == 10)); then printf 'X'; else printf '%s' "$check"; fi
}

valid_isbn10() { [[ $(expected_isbn10 "$1") == "${1: -1}" ]]; }

explain_isbn10() {
  local sum
  weighted_sum "${1:0:9}" 10 9 8 7 6 5 4 3 2 >/dev/null
  sum=$(weighted_sum "${1:0:9}" 10 9 8 7 6 5 4 3 2)
  echo "Multiply the first nine digits by 10, 9, 8 ... 2:"
  echo "$WORKING = $sum"
  echo "The check digit tops the sum up to a multiple of 11: (11 - $((sum % 11))) mod 11 = $(((11 - sum % 11) % 11))  (10 is written X)"
}

# ---- ISSN: weights 8..2, modulo 11 --------------------------------------------

fits_issn() { [[ $1 =~ ^[0-9]{7}[0-9X]$ ]]; }

expected_issn() {
  local sum check
  sum=$(weighted_sum "${1:0:7}" 8 7 6 5 4 3 2)
  check=$(((11 - sum % 11) % 11))
  if ((check == 10)); then printf 'X'; else printf '%s' "$check"; fi
}

valid_issn() { [[ $(expected_issn "$1") == "${1: -1}" ]]; }

explain_issn() {
  local sum
  weighted_sum "${1:0:7}" 8 7 6 5 4 3 2 >/dev/null
  sum=$(weighted_sum "${1:0:7}" 8 7 6 5 4 3 2)
  echo "Multiply the first seven digits by 8, 7, 6 ... 2:"
  echo "$WORKING = $sum"
  echo "The check digit tops the sum up to a multiple of 11: (11 - $((sum % 11))) mod 11 = $(((11 - sum % 11) % 11))  (10 is written X)"
}

# ---- Luhn: payment cards and IMEIs --------------------------------------------
# From the right, double every second digit; if that gives two digits, add them.

luhn_sum() { # prints the Luhn sum of the body (everything except the last digit)
  local body=$1 sum=0 i d text=""
  for ((i = ${#body} - 1; i >= 0; i--)); do
    d=${body:i:1}
    if (((${#body} - i) % 2 == 1)); then
      d=$((d * 2))
      ((d > 9)) && d=$((d - 9))
    fi
    sum=$((sum + d))
    text="$d${text:+ + }$text"
  done
  WORKING=$text
  printf '%s' "$sum"
}

expected_luhn() {
  local sum
  sum=$(luhn_sum "${1:0:${#1}-1}")
  printf '%s' $(((10 - sum % 10) % 10))
}

explain_luhn() {
  local sum
  luhn_sum "${1:0:${#1}-1}" >/dev/null
  sum=$(luhn_sum "${1:0:${#1}-1}")
  echo "Working leftwards from the check digit, double every second digit (16 becomes 1+6 = 7):"
  echo "$WORKING = $sum"
  echo "The check digit tops the sum up to a multiple of 10: (10 - $((sum % 10))) mod 10 = $(((10 - sum % 10) % 10))"
}

fits_card() { is_digits "$1" && ((${#1} >= 13 && ${#1} <= 19)); }
expected_card() { expected_luhn "$1"; }
valid_card() { [[ $(expected_luhn "$1") == "${1: -1}" ]]; }
explain_card() {
  explain_luhn "$1"
  echo "Card network by its first digits: $(card_network "$1")"
}

card_network() {
  local n=$1 two=${1:0:2} four=${1:0:4}
  if [[ ${n:0:1} == 4 ]]; then
    echo "Visa"
  elif ((10#$two >= 51 && 10#$two <= 55)) || ((10#$four >= 2221 && 10#$four <= 2720)); then
    echo "Mastercard"
  elif [[ $two == 34 || $two == 37 ]]; then
    echo "American Express"
  else
    echo "not one this tool recognises"
  fi
}

fits_imei() { is_digits "$1" && ((${#1} == 15)); }
expected_imei() { expected_luhn "$1"; }
valid_imei() { valid_card "$1"; }
explain_imei() { explain_luhn "$1"; }

# ---- Australian Business Number: 11 digits, modulo 89 -------------------------

fits_abn() { is_digits "$1" && ((${#1} == 11)) && [[ ${1:0:1} != 0 ]]; }

abn_sum() {
  local shifted=$((${1:0:1} - 1))${1:1}
  weighted_sum "$shifted" 10 1 3 5 7 9 11 13 15 17 19
}

valid_abn() { (($(abn_sum "$1") % 89 == 0)); }

# The ABN's two check digits come first, so there is no single "expected last digit".
expected_abn() { printf '?'; }

explain_abn() {
  local sum
  abn_sum "$1" >/dev/null
  sum=$(abn_sum "$1")
  echo "Subtract 1 from the first digit, then multiply by 10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19:"
  echo "$WORKING = $sum"
  echo "A valid ABN leaves no remainder when divided by 89: $sum mod 89 = $((sum % 89))"
}

# ---- Australian Company Number: 9 digits, weights 8..1, modulo 10 --------------

fits_acn() { is_digits "$1" && ((${#1} == 9)); }

expected_acn() {
  local sum
  sum=$(weighted_sum "${1:0:8}" 8 7 6 5 4 3 2 1)
  printf '%s' $(((10 - sum % 10) % 10))
}

valid_acn() { [[ $(expected_acn "$1") == "${1: -1}" ]]; }

explain_acn() {
  local sum
  weighted_sum "${1:0:8}" 8 7 6 5 4 3 2 1 >/dev/null
  sum=$(weighted_sum "${1:0:8}" 8 7 6 5 4 3 2 1)
  echo "Multiply the first eight digits by 8, 7, 6 ... 1:"
  echo "$WORKING = $sum"
  echo "The check digit tops the sum up to a multiple of 10: (10 - $((sum % 10))) mod 10 = $(((10 - sum % 10) % 10))"
}

# ---- Australian Tax File Number: 9 digits, modulo 11 ---------------------------

fits_tfn() { is_digits "$1" && ((${#1} == 9)); }
tfn_sum() { weighted_sum "$1" 1 4 3 7 5 8 6 9 10; }
valid_tfn() { (($(tfn_sum "$1") % 11 == 0)); }

expected_tfn() { # the last digit d must satisfy (partial + 10d) mod 11 == 0
  local partial d
  partial=$(weighted_sum "${1:0:8}" 1 4 3 7 5 8 6 9)
  for d in 0 1 2 3 4 5 6 7 8 9; do
    if (((partial + 10 * d) % 11 == 0)); then
      printf '%s' "$d"
      return
    fi
  done
  printf '?' # no digit works: the first eight digits cannot belong to a TFN
}

explain_tfn() {
  local sum
  tfn_sum "$1" >/dev/null
  sum=$(tfn_sum "$1")
  echo "Multiply the nine digits by 1, 4, 3, 7, 5, 8, 6, 9, 10:"
  echo "$WORKING = $sum"
  echo "A valid TFN leaves no remainder when divided by 11: $sum mod 11 = $((sum % 11))"
}

# ---- Australian Medicare card: the NINTH digit checks the first eight ----------

fits_medicare() { is_digits "$1" && [[ ${#1} == 10 || ${#1} == 11 ]] && [[ ${1:0:1} == [2-6] ]]; }

expected_medicare() {
  local sum
  sum=$(weighted_sum "${1:0:8}" 1 3 7 9 1 3 7 9)
  printf '%s' $((sum % 10))
}

valid_medicare() { [[ $(expected_medicare "$1") == "${1:8:1}" ]]; }

explain_medicare() {
  local sum
  weighted_sum "${1:0:8}" 1 3 7 9 1 3 7 9 >/dev/null
  sum=$(weighted_sum "${1:0:8}" 1 3 7 9 1 3 7 9)
  echo "Multiply the first eight digits by 1, 3, 7, 9, 1, 3, 7, 9:"
  echo "$WORKING = $sum"
  echo "The ninth digit is the last digit of that sum: $sum mod 10 = $((sum % 10))"
  echo "(The digits after it are the issue number and your line on the card.)"
}

# ---- IBAN: letters become numbers, then modulo 97 ------------------------------

fits_iban() { [[ $1 =~ ^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$ ]]; }

# mod97 TEXT -> remainder of the number you get by writing A=10 ... Z=35.
# The number can be 60 digits long, far too big for normal arithmetic, so the
# remainder is carried along one digit at a time, as in long division.
mod97() {
  local text=$1 r=0 i c value
  for ((i = 0; i < ${#text}; i++)); do
    c=${text:i:1}
    if [[ $c == [0-9] ]]; then
      r=$(((r * 10 + c) % 97))
    else
      printf -v value '%d' "'$c"
      value=$((value - 55)) # "A" is character 65, and must become 10
      r=$(((r * 100 + value) % 97))
    fi
  done
  printf '%s' "$r"
}

valid_iban() { (($(mod97 "${1:4}${1:0:4}") == 1)); }

expected_iban() { # the two check digits, positions 3 and 4
  local r
  r=$(mod97 "${1:4}${1:0:2}00")
  printf '%02d' $((98 - r))
}

explain_iban() {
  echo "Move the first four characters to the end and write letters as numbers (A=10 ... Z=35)."
  echo "A valid IBAN then leaves remainder 1 when divided by 97: remainder = $(mod97 "${1:4}${1:0:4}")"
  echo "(Its check digits are characters 3 and 4: expected $(expected_iban "$1"), found ${1:2:2}.)"
}
