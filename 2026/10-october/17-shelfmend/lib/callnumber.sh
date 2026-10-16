# shellcheck shell=bash
# KEY, SCHEME and WHY are results read by the caller.
# shellcheck disable=SC2034
# Turns a library call number into a sort key: a plain string that sorts correctly with a
# byte-by-byte comparison (LC_ALL=C), so the rest of the program never has to know the rules.
#
# Library of Congress, e.g.  QA76.73 .P98 S65 2019 v.2
#   class letters  QA      padded to 3 with spaces, so Q < QA < QAA
#   class number   76.73   whole part padded to 5 digits, decimal part padded right to 8
#   cutters        .P98    compared as DECIMALS: P98 < P983 < P99, so digits are padded right
#   then a year, a volume (v.2) and a copy (c.2), each compared as numbers
# Dewey, e.g.  823.914 ROW
#   number 823.914, then the letters of the author mark
#
# Elements are compared one by one; a missing element sorts first ("nothing before something"),
# and at the same position a cutter sorts before a year, a year before a volume, a volume before a copy.

# The key uses only these bytes:  space < 0-9 < A-Z < a-z, which is the C locale's order.
export LC_ALL=C

# Results are returned in these globals (no subshells, so 20,000 lines stay fast).
KEY=''
SCHEME=''
WHY=''

_pad_right() { # _pad_right DIGITS WIDTH -> REPLY, digits padded with zeros on the right
  local d=$1 w=$2
  while ((${#d} < w)); do d+='0'; done
  REPLY=${d:0:w}
}

_tail_tokens() { # _tail_tokens "REST" -> appends the encoded cutters, year, volume and copy to KEY
  local rest=$1 tok part
  rest=${rest//v. /v.}
  rest=${rest//c. /c.}
  for tok in $rest; do
    # "v.2", "v2", "c.2": volume and copy (a leading dot would make it a cutter, ".V2").
    if [[ $tok =~ ^[vV]\.?([0-9]{1,4})$ ]]; then
      printf -v REPLY '%04d' "$((10#${BASH_REMATCH[1]}))"
      KEY+=" v$REPLY"
      continue
    fi
    if [[ $tok =~ ^[cC]\.([0-9]{1,3})$ || $tok =~ ^c([0-9]{1,3})$ ]]; then
      printf -v REPLY '%03d' "$((10#${BASH_REMATCH[1]}))"
      KEY+=" x$REPLY"
      continue
    fi
    # Anything else is cutters and a year, possibly run together: ".P98.S65", "S65", "2019".
    for part in ${tok//./ }; do
      if [[ $part =~ ^([A-Za-z])([0-9]{1,8})([A-Za-z]{0,2})$ ]]; then
        _pad_right "${BASH_REMATCH[2]}" 8
        KEY+=" c${BASH_REMATCH[1]^^}$REPLY${BASH_REMATCH[3]^^}"
      elif [[ $part =~ ^([0-9]{4})([a-z]?)$ ]]; then
        KEY+=" d${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
      else
        WHY="part '$part' isn't a cutter, year, volume or copy"
        return 1
      fi
    done
  done
  return 0
}

# callnumber_key "CALL NUMBER" [lc|dewey|auto] -> sets KEY and SCHEME, or WHY and returns 1
callnumber_key() {
  local raw=$1 want=${2:-auto} cn
  KEY='' SCHEME='' WHY=''
  # Normalise: upper-case class and cutters, single spaces, "v. 2" -> "v.2".
  cn=$raw
  cn=${cn//$'\t'/ }
  while [[ $cn == *'  '* ]]; do cn=${cn//  / }; done
  cn=${cn# }
  cn=${cn% }
  if [[ $want != dewey && $cn =~ ^([A-Za-z]{1,3})\ ?([0-9]{1,5})(\.([0-9]{1,8}))?(\ ?(.*))?$ ]]; then
    local letters=${BASH_REMATCH[1]^^} whole=${BASH_REMATCH[2]} dec=${BASH_REMATCH[4]} rest=${BASH_REMATCH[6]}
    printf -v KEY '%-3s %05d ' "$letters" "$((10#$whole))"
    _pad_right "$dec" 8
    KEY+=$REPLY
    SCHEME=lc
    _tail_tokens "$rest" || return 1
    return 0
  fi
  if [[ $want != lc && $cn =~ ^([0-9]{3})(\.([0-9]{1,10}))?(\ +(.*))?$ ]]; then
    local num=${BASH_REMATCH[1]} dec=${BASH_REMATCH[3]} mark=${BASH_REMATCH[5]^^} tok
    _pad_right "$dec" 10
    KEY="$num.$REPLY"
    for tok in $mark; do
      if [[ $tok =~ ^[A-Z][A-Z0-9]{0,11}$ ]]; then
        KEY+=" $tok"
      elif [[ $tok =~ ^([0-9]{4})$ ]]; then
        KEY+=" d$tok"
      else
        WHY="author mark '$tok' should be letters and digits"
        return 1
      fi
    done
    SCHEME=dewey
    return 0
  fi
  case $want in
    lc) WHY="not a Library of Congress call number (like QA76.73 .P98 2019)" ;;
    dewey) WHY="not a Dewey number (like 823.914 ROW)" ;;
    *) WHY="not a Library of Congress or Dewey call number" ;;
  esac
  return 1
}
