# shellcheck shell=bash
# KEY and SCHEME are set by callnumber_key (lib/callnumber.sh).
# shellcheck disable=SC2153
# Reading the shelf list, and the report.

CALLS=()   # call numbers as written (cleaned)
TITLES=()  # optional titles
KEYS=()    # sort keys from callnumber_key
SCHEMES=() # lc or dewey, per book

# shelf_read "TEXT" SCHEME -> fills the arrays above, or prints an error and returns 1
shelf_read() {
  local text=$1 want=$2 line n=0 call title
  local bidi=$'\xe2\x80\xaa|\xe2\x80\xab|\xe2\x80\xac|\xe2\x80\xad|\xe2\x80\xae|\xe2\x81\xa6|\xe2\x81\xa7|\xe2\x81\xa8|\xe2\x81\xa9|\xe2\x80\x8e|\xe2\x80\x8f'
  local -a bad=()
  CALLS=() TITLES=() KEYS=() SCHEMES=()
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    if ((${#line} > MAX_LINE)); then
      printf 'shelfmend: line %d is longer than %d characters\n' "$n" "$MAX_LINE" >&2
      return 1
    fi
    # Control characters (terminal escapes) and hidden direction marks are refused outright.
    line=${line//$'\t'/ }
    if [[ $line =~ [[:cntrl:]] || $line == *$'\x7f'* || $line =~ $bidi ]]; then
      printf 'shelfmend: line %d contains control or hidden direction characters\n' "$n" >&2
      return 1
    fi
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    call=${line%%|*}
    title=''
    [[ $line == *'|'* ]] && title=${line#*|}
    title=${title# }
    title=${title% }
    call=${call% }
    if ((${#CALLS[@]} >= MAX_BOOKS)); then
      printf 'shelfmend: more than %d books\n' "$MAX_BOOKS" >&2
      return 1
    fi
    if callnumber_key "$call" "$want"; then
      CALLS+=("${call# }")
      TITLES+=("$title")
      KEYS+=("$KEY")
      SCHEMES+=("$SCHEME")
    else
      bad+=("line $n: $WHY")
    fi
  done <<<"$text"
  if ((${#bad[@]})); then
    printf 'shelfmend: some call numbers could not be read; fix them and run again:\n' >&2
    local b shown=0
    for b in "${bad[@]}"; do
      ((shown++ < 10)) || break
      printf '  %s\n' "$b" >&2
    done
    ((${#bad[@]} > 10)) && printf '  ...and %d more\n' $((${#bad[@]} - 10)) >&2
    return 1
  fi
  return 0
}

_book() { # _book INDEX -> REPLY = "call number  (title)"
  REPLY=${CALLS[$1]}
  if [[ -n ${TITLES[$1]} ]]; then REPLY+="  (${TITLES[$1]})"; fi
}

# shelf_report NAME -> prints the report using KEYS, KEEP and KEPT
shelf_report() {
  local name=$1 n=${#KEYS[@]} i j moves naive=0 misled=0 lc=0 dewey=0 kind
  for ((i = 0; i < n; i++)); do
    [[ ${SCHEMES[i]} == lc ]] && lc=$((lc + 1)) || dewey=$((dewey + 1))
    if ((i > 0)) && [[ ${KEYS[i]} < ${KEYS[i - 1]} ]]; then
      naive=$((naive + 1))
      ((KEEP[i])) && misled=$((misled + 1))
    fi
  done
  if ((lc && dewey)); then kind="mixed: $lc Library of Congress, $dewey Dewey"
  elif ((lc)); then kind='Library of Congress'
  else kind='Dewey'; fi
  moves=$((n - KEPT))
  printf 'SHELFMEND  %s  (%d books, %s)\n\n' "$name" "$n" "$kind"
  if ((moves == 0)); then
    printf 'The shelf is in order. Nothing to move.\n'
    return 0
  fi
  local s=s
  ((moves == 1)) && s=''
  local rest="the other $KEPT are"
  ((KEPT == 1)) && rest='the other one is'
  printf 'Move %d book%s and the shelf is in order; %s already in sequence.\n' "$moves" "$s" "$rest"
  if ((misled)); then
    local flagged="$naive books, and $misled of them are"
    ((naive == 1)) && flagged='1 book, and it is'
    ((naive > 1 && misled == 1)) && flagged="$naive books, and 1 of them is"
    printf '(A book-by-book check, comparing each book with the one before it, flags %s\n' "$flagged"
    printf ' actually in the right place: a misplaced book makes the good book after it look wrong.)\n'
  fi
  printf '\n'

  # Where does each book go? After the last book that stays and sorts at or before it.
  local -a stay=() order=()
  for ((i = 0; i < n; i++)); do ((KEEP[i])) && stay+=("$i"); done
  local -A dest=()
  for ((i = 0; i < n; i++)); do
    ((KEEP[i])) && continue
    local lo=0 hi=${#stay[@]} mid
    while ((lo < hi)); do
      mid=$(((lo + hi) / 2))
      if [[ ${KEYS[stay[mid]]} > ${KEYS[i]} ]]; then hi=$mid; else lo=$((mid + 1)); fi
    done
    dest[$i]=$((lo - 1)) # index into stay[], or -1 for the start of the shelf
    order+=("$i")
  done

  printf 'TAKE OUT (left to right)                     PUT BACK\n'
  local num=0 target
  for i in "${order[@]}"; do
    num=$((num + 1))
    _book "$i"
    printf '%3d. position %-5d %s\n' "$num" $((i + 1)) "$REPLY"
    target=${dest[$i]}
    if ((target < 0)); then
      _book "${stay[0]}"
      printf '     -> at the start, before position %d: %s\n' $((stay[0] + 1)) "$REPLY"
    else
      j=${stay[target]}
      _book "$j"
      printf '     -> after position %d: %s\n' $((j + 1)) "$REPLY"
    fi
  done

  # Several books going into the same gap need putting back in the right order among themselves.
  local -A gap=()
  for i in "${order[@]}"; do gap[${dest[$i]}]+="$i "; done
  local g first=1 members sorted
  for g in $(printf '%s\n' "${!gap[@]}" | sort -n); do
    read -r -a members <<<"${gap[$g]}"
    ((${#members[@]} > 1)) || continue
    if ((first)); then printf '\nBOOKS GOING INTO THE SAME GAP (put them back in this order)\n'; first=0; fi
    sorted=$(for i in "${members[@]}"; do printf '%s\t%s\n' "${KEYS[i]}" "$i"; done | sort -s -t $'\t' -k1,1 | cut -f2)
    local list=''
    for i in $sorted; do list+="${CALLS[i]}, "; done
    if ((g < 0)); then printf '  at the start: %s\n' "${list%, }"
    else printf '  after position %d: %s\n' $((stay[g] + 1)) "${list%, }"; fi
  done
  printf '\nPositions are counted from the left as scanned, before anything is moved.\n'
}
