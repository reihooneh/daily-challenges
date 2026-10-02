#!/bin/sh
# End-to-end tests for the command-line program. Usage: cli_test.sh ./earprint
set -u
BIN="$1"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
pass=0; fail=0

check() { # check "description" expected_exit actual_exit
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi
}
contains() { # contains "description" "needle" "haystack"
    case "$3" in *"$2"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); echo "FAIL: $1 (missing '$2')" ;; esac
}

printf 'abc' > "$DIR/a.txt"
printf 'abc' > "$DIR/same.txt"
printf 'abd' > "$DIR/b.txt"

out=$("$BIN" "$DIR/a.txt"); check "hash a file" 0 $?
contains "known SHA-256 of abc" "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" "$out"
contains "melody line" "melody  " "$out"

"$BIN" --compare "$DIR/a.txt" "$DIR/same.txt" >/dev/null; check "identical files match" 0 $?
"$BIN" --compare "$DIR/a.txt" "$DIR/b.txt" >/dev/null; check "different files differ" 1 $?

"$BIN" "$DIR/a.txt" -o "$DIR/tune.wav" >/dev/null; check "write wav" 0 $?
head -c 4 "$DIR/tune.wav" | grep -q RIFF; check "wav starts with RIFF" 0 $?
"$BIN" "$DIR/a.txt" -o "$DIR/tune.wav" >/dev/null 2>&1; check "refuses to overwrite" 2 $?
"$BIN" "$DIR/a.txt" -o "$DIR/tune.wav" --force >/dev/null; check "--force overwrites" 0 $?

# A symlink must not be followed to clobber another file.
printf 'precious' > "$DIR/precious.txt"
ln -s "$DIR/precious.txt" "$DIR/link.wav"
"$BIN" "$DIR/a.txt" -o "$DIR/link.wav" >/dev/null 2>&1; check "refuses to write through a symlink" 2 $?
contains "symlink target untouched" "precious" "$(cat "$DIR/precious.txt")"

# Bad input: every case must exit 2 with a message, never crash.
"$BIN" >/dev/null 2>&1; check "no arguments" 2 $?
"$BIN" "$DIR/missing.txt" >/dev/null 2>&1; check "missing file" 2 $?
"$BIN" "$DIR" >/dev/null 2>&1; check "directory instead of file" 2 $?
"$BIN" --bogus >/dev/null 2>&1; check "unknown option" 2 $?
"$BIN" "$DIR/a.txt" -o >/dev/null 2>&1; check "-o without a name" 2 $?
"$BIN" --compare "$DIR/a.txt" >/dev/null 2>&1; check "--compare with one file" 2 $?
"$BIN" "$DIR/a.txt" "$DIR/b.txt" >/dev/null 2>&1; check "two inputs without --compare" 2 $?

# Hostile file names are data, not format strings or commands.
evil="$DIR/%s%s%n;\$(id).txt"
printf 'x' > "$evil"
out=$("$BIN" "$evil"); check "format-string file name" 0 $?
contains "evil name printed literally" '%s%s%n' "$out"
long=$(printf 'A%.0s' $(seq 1 5000))
"$BIN" "$DIR/$long" >/dev/null 2>&1; check "5000-character path" 2 $?

# Empty and binary input.
: > "$DIR/empty"
out=$("$BIN" "$DIR/empty"); check "empty file" 0 $?
contains "SHA-256 of nothing" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" "$out"
head -c 300000 /dev/urandom > "$DIR/random.bin"
out=$("$BIN" "$DIR/random.bin"); check "300 kB of random bytes" 0 $?
contains "matches sha256sum" "$(sha256sum "$DIR/random.bin" | cut -d' ' -f1)" "$out"

echo "$pass CLI checks passed, $fail failed"
[ "$fail" -eq 0 ]
