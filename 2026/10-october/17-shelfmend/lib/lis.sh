# shellcheck shell=bash
# KEEP and KEPT are results read by the caller.
# shellcheck disable=SC2034
# The longest run of books that are already in order (a longest non-decreasing subsequence).
# Every book outside that run must move, and no smaller set of moves can fix the shelf:
# books that stay put must already be in order, so at most this many can stay.
#
# Patience sorting, O(n log n): tails[k] holds the index of the smallest possible last key of
# an in-order run of length k+1. Each new key goes on the first pile whose top is bigger.

# lis_keep KEYS_ARRAY_NAME -> sets the global array KEEP (1 = stays, 0 = moves) and KEPT (count)
lis_keep() {
  local -n _keys=$1
  local n=${#_keys[@]} i lo hi mid len=0 k
  local -a tails=() prev=()
  KEEP=()
  for ((i = 0; i < n; i++)); do
    # First pile whose top key is strictly greater (so equal keys can stay side by side).
    lo=0
    hi=$len
    while ((lo < hi)); do
      mid=$(((lo + hi) / 2))
      if [[ ${_keys[tails[mid]]} > ${_keys[i]} ]]; then hi=$mid; else lo=$((mid + 1)); fi
    done
    if ((lo > 0)); then prev[i]=${tails[lo - 1]}; else prev[i]=-1; fi
    tails[lo]=$i
    ((lo == len)) && len=$((len + 1))
    KEEP[i]=0
  done
  KEPT=$len
  ((len == 0)) && return 0
  # Walk back from the end of the longest run.
  k=${tails[len - 1]}
  while ((k >= 0)); do
    KEEP[k]=1
    k=${prev[k]}
  done
}
