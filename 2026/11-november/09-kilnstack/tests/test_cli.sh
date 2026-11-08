#!/usr/bin/env bash
# Runs the command as a user would, including hostile input. Usage: tests/test_cli.sh BINARY
set -uo pipefail
BIN=$1
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
pass=0 fail=0
check() { if "${@:2}"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL  $1"; fi; }

out=$("$BIN" "$HERE/../examples/studio-glaze.txt"); code=$?
check 'the example runs' [ "$code" = 0 ]
check 'the summary' grep -q 'KILNSTACK  glaze firing, 46 cm kiln 66 cm tall, half shelves: 33 pieces' <<<"$out"
out=$("$BIN" - < "$HERE/../examples/studio-glaze.txt"); check 'standard input' grep -q 'Firing 1' <<<"$out"

dir=$(mktemp -d)
ln -s "$HERE/../examples/studio-glaze.txt" "$dir/link.txt"
"$BIN" "$dir/link.txt" >/dev/null 2>"$dir/e"; check 'a link is refused' [ $? = 2 ]
"$BIN" "$dir" >/dev/null 2>"$dir/e"; check 'a folder is refused' grep -q 'regular files' "$dir/e"
"$BIN" "$dir/SECRET-missing" >/dev/null 2>"$dir/e"; check 'the path is never echoed' bash -c '! grep -q SECRET "$1"' _ "$dir/e"
printf 'posts 5\npiece 9 5 $(touch %s/pwned)\n' "$dir" | "$BIN" - >/dev/null 2>&1
check 'nothing runs' [ ! -e "$dir/pwned" ]
head -c 70000 /dev/zero | tr '\0' '#' | "$BIN" - >/dev/null 2>"$dir/e"; check 'over 64 KB' grep -q '64 KB' "$dir/e"
"$BIN" >/dev/null 2>&1; check 'usage' [ $? = 2 ]
rm -rf -- "$dir"
echo "$pass command checks passed, $fail failed"
[ "$fail" = 0 ]
