#!/usr/bin/env bash
# Command-line tests. Usage: tests/test_cli.sh PATH_TO_BINARY
set -uo pipefail
BIN=$1
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EX="$HERE/../examples/masters.txt"
passed=0 failed=0
check() { if eval "$2"; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL  $1"; fi; }

out=$("$BIN" "$EX"); code=$?
check 'example runs' '[[ $code == 0 ]]'
check 'five lanes' '[[ $(grep -c "^Lane " <<<"$out") == 5 ]]'
check 'lane 1 on 1:35' '[[ $out == *"Lane 1   on 1:35"* ]]'
check 'compares with equal lanes' '[[ $out == *"Equal-sized lanes by pace would give"* ]]'
check 'stdin gives the same sheet' '[[ $("$BIN" - <"$EX") == "$out" ]]'
slow=$(sed 's/^lanes 5/lanes 5\nlane-1 slowest/' "$EX" | "$BIN" -)
check 'lane 1 can be the slowest' '[[ $slow == *"Lane 1   on 2:35"* ]]'
"$BIN" /dev/zero >/dev/null 2>&1; check '/dev/zero refused' '[[ $? == 2 ]]'
"$BIN" "$HERE" >/dev/null 2>&1; check 'directory refused' '[[ $? == 2 ]]'
tmp=$(mktemp -d)
ln -s "$EX" "$tmp/link.txt"
"$BIN" "$tmp/link.txt" >/dev/null 2>&1; check 'symlink refused' '[[ $? == 2 ]]'
rm -rf "$tmp"
err=$("$BIN" secret-name-zz.txt 2>&1); check 'the path is never echoed' '[[ $err != *secret-name* ]]'
err=$(printf 'swimmer Ann 1:20\n\033]0;pwned\007\n' | "$BIN" - 2>&1); code=$?
check 'escape codes refused, not echoed' '[[ $code == 2 && $err != *pwned* ]]'
head -c 100000 /dev/zero | tr '\0' '#' | "$BIN" - >/dev/null 2>&1; check 'big input refused' '[[ $? == 2 ]]'
"$BIN" a b >/dev/null 2>&1; check 'two files refused' '[[ $? == 2 ]]'
"$BIN" >/dev/null 2>&1; check 'no file refused' '[[ $? == 2 ]]'
"$BIN" --help | grep -q Usage; check 'help' '[[ $? == 0 ]]'

echo "$passed passed, $failed failed (command line)"
((failed == 0))
