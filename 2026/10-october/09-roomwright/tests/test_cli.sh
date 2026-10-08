#!/usr/bin/env bash
# Command-line tests: exit codes, hostile input, and errors that never echo input.
set -u
bin=${1:?usage: test_cli.sh PATH_TO_ROOMWRIGHT}
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0 fail=0

expect() { # expect NAME WANTED_EXIT ACTUAL_EXIT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: wanted exit $2, got $3"; fi
}
contains() { # contains NAME FILE TEXT
    if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: missing '$3'"; fi
}
lacks() { # lacks NAME FILE TEXT
    if grep -qF -- "$3" "$2"; then fail=$((fail + 1)); echo "FAIL $1: echoed '$3'"; else pass=$((pass + 1)); fi
}

"$bin" "$here/examples/clockmaker.room" >"$work/out" 2>"$work/err"
expect example 1 $?
contains example "$work/out" "'cabinet' uses up brass_key, which 'chest' still needs."
contains example "$work/out" "4 players finish in about 24 minutes"
contains example "$work/out" "P4     .....FFFF.............HH"

"$bin" - <"$here/examples/clockmaker.room" >"$work/out" 2>&1
expect stdin 1 $?

printf 'start a\npuzzle one 3 : a -> b\npuzzle door 2 : b -> EXIT\n' >"$work/good.room"
"$bin" "$work/good.room" >"$work/out" 2>&1
expect clean-room 0 $?
contains clean-room "$work/out" "No problems found."

"$bin" --players 1 "$here/examples/clockmaker.room" >"$work/out" 2>&1
expect one-player 1 $?
contains one-player "$work/out" "1 player finishes in about 39 minutes"

sed 's/^limit  45/limit 30/' "$here/examples/clockmaker.room" >"$work/tight.room"
"$bin" --players 1 "$work/tight.room" >"$work/out" 2>&1
expect over-limit 1 $?
contains over-limit "$work/out" "about 39 minutes with 1 player, over the 30 minute limit"

for args in "" "--players" "--players 0" "--players 13" "--players 1e1" "--players -3" "--bogus x" \
            "/no/such/file" "/" "a b"; do
    # shellcheck disable=SC2086  # deliberate word splitting of the argument list
    "$bin" $args >"$work/out" 2>"$work/err"
    expect "args[$args]" 2 $?
    [ -s "$work/out" ] && { fail=$((fail + 1)); echo "FAIL args[$args]: wrote to stdout"; }
done

evil=$'\e]0;owned\a$(reboot)'
"$bin" "$evil" >"$work/out" 2>"$work/err"
expect evil-name 2 $?
lacks evil-name "$work/err" "owned"
lacks evil-name "$work/err" "reboot"

printf 'puzzle <img/onerror=alert(1)> 1 : -> EXIT\n' >"$work/xss.room"
"$bin" "$work/xss.room" >"$work/out" 2>"$work/err"
expect markup 2 $?
contains markup "$work/err" "line 1: the puzzle name is not valid"
lacks markup "$work/err" "onerror"

head -c 70000 /dev/zero | tr '\0' '\n' >"$work/big.room"
"$bin" "$work/big.room" >"$work/out" 2>"$work/err"
expect too-large 2 $?
contains too-large "$work/err" "larger than 64 KB"

# An endless stream is cut off after 64 KB instead of filling memory.
timeout 10 "$bin" /dev/zero >"$work/out" 2>"$work/err"
expect endless-stream 2 $?

head -c 3000 /dev/urandom >"$work/noise.room"
"$bin" "$work/noise.room" >"$work/out" 2>"$work/err"
expect binary-noise 2 $?

echo "$pass CLI checks passed, $fail failed"
[ "$fail" -eq 0 ]
