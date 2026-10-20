#!/usr/bin/env bash
# Command-line tests. Usage: tests/test_cli.sh PATH_TO_BINARY
set -uo pipefail
BIN=$1
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
passed=0 failed=0
check() { if eval "$2"; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL  $1"; fi; }

out=$("$BIN" "$HERE/../examples/comma-pump.txt"); code=$?
check 'example runs' '[[ $code == 0 ]]'
check 'reports the syntonic comma' '[[ $out == *"21.5 cents lower"*"syntonic comma"* ]]'
check 'lists five chords' '[[ $(grep -c "^ *[0-9] " <<<"$out") == 5 ]]'
out=$("$BIN" - --hz < "$HERE/../examples/comma-pump.txt")
check 'reads stdin, shows Hz' '[[ $out == *"standard input"* && $out == *" Hz)"* ]]'
"$BIN" /dev/zero >/dev/null 2>&1; check '/dev/zero refused' '[[ $? == 2 ]]'
"$BIN" "$HERE" >/dev/null 2>&1; check 'directory refused' '[[ $? == 2 ]]'
tmp=$(mktemp -d)
ln -s "$HERE/../examples/comma-pump.txt" "$tmp/link.txt"
"$BIN" "$tmp/link.txt" >/dev/null 2>&1; check 'symlink refused' '[[ $? == 2 ]]'
cp "$HERE/../examples/comma-pump.txt" "$tmp/$(printf 'x\033[31m.txt')"
out=$("$BIN" "$tmp/"x*.txt); check 'file name cleaned' '[[ $out != *$'"'"'\e'"'"'* ]]'
rm -rf "$tmp"
err=$(printf 'C4 E4 G4\n\033]0;pwned\007\n' | "$BIN" - 2>&1); code=$?
check 'escape codes refused, not echoed' '[[ $code == 2 && $err != *pwned* ]]'
head -c 100000 /dev/zero | tr '\0' 'C' | "$BIN" - >/dev/null 2>&1; check 'big input refused' '[[ $? == 2 ]]'
"$BIN" a b >/dev/null 2>&1; check 'two files refused' '[[ $? == 2 ]]'
"$BIN" --nope >/dev/null 2>&1; check 'unknown option refused' '[[ $? == 2 ]]'
"$BIN" --help | grep -q Usage; check 'help' '[[ $? == 0 ]]'

echo "$passed passed, $failed failed (command line)"
((failed == 0))
