# Earprint 🎵

**A fingerprint for your ears: hear whether two files are the same.**

When you download software, you're supposed to compare its SHA-256 fingerprint with the official one. That means checking 64 random characters by eye, and almost nobody does it properly. Earprint turns the fingerprint into a 16-note melody. The same file always plays the same tune. Change a single byte and the tune is completely different.

## What makes it different

SSH has "randomart", a little picture of a key's fingerprint so humans can spot changes at a glance. Earprint is the same idea for your ears. "Audio fingerprinting" tools usually go the other way (recognising a song from its sound); this goes from a file's hash *to* sound.

## Features

- **SHA-256 implemented from the standard** (FIPS 180-4), verified against NIST's official test vectors and against `sha256sum`
- **Melody from the hash:** 16 notes on a pentatonic scale, so every fingerprint sounds pleasant, like a wind chime
- **WAV export** with a bell-like tone, no audio libraries needed
- **`--compare` mode** for scripts: exit code `0` if two files match, `1` if they differ
- **Constant memory:** files are read in 64 kB chunks, so a 10 GB file uses no more memory than a 10 byte one
- **No dependencies:** C11 and the standard library only

## Example

```text
$ earprint app.bin -o app.wav
app.bin
  sha256  53a6b9a8b477a2320dea6f14d7e4b5e9d64c556655bd357f0e08a8f80e9c74a4
  melody  G4 C5 C4~ E4 G4 D4 C5 D4~ A4 C5 C5~ G4~ A4 G5 A4 D5
  saved   app.wav (3.6 seconds)
```

One extra space added to the file:

```text
$ earprint --compare app.bin app-tampered.bin
app.bin
  sha256  53a6b9a8b477a2320dea6f14d7e4b5e9d64c556655bd357f0e08a8f80e9c74a4
  melody  G4 C5 C4~ E4 G4 D4 C5 D4~ A4 C5 C5~ G4~ A4 G5 A4 D5
app-tampered.bin
  sha256  c546fc85c826c2013db62d9415863fa8259d5b569ae12de1aead90906b8f6959
  melody  E5 E4~ C4 A4~ D4 C5 D4 G4 E5~ D4 A4~ C5~ A4~ A4 E5~ C5~

DIFFERENT: these are not the same file.
```

`~` marks a long note.

## Tech

C11, standard library only (`-lm` for sine waves). Built with `make`; tested with AddressSanitizer, UndefinedBehaviorSanitizer and Valgrind.

## Build and run

```bash
cd 2026/10-october/03-earprint
make
./earprint somefile.zip -o tune.wav
./earprint --compare download.zip original.zip
```

| Exit code | Meaning |
|---|---|
| `0` | Success, or the files match |
| `1` | The files differ (`--compare`) |
| `2` | Error (bad option, unreadable file, output already exists) |

## Tests

```bash
make test
```

- **151 unit checks:** NIST test vectors (including one million `a`s), every padding edge case of SHA-256, the note mapping, text and audio rendering with too-small buffers, and the exact bytes of the WAV header
- **25 command-line checks:** real files, exit codes, overwrite and symlink protection, hostile file names, empty and random binary input
- Both suites run with memory-safety sanitizers switched on, so any out-of-bounds read or write fails the run

## Security

C gives no safety net, so this project is deliberately defensive:

- **No buffer overflows by construction:** every buffer has a documented maximum, every copy is length-checked, and `snprintf` is used so text can never overrun. Functions refuse a too-small buffer instead of writing past it.
- **Checked arithmetic:** sizes are checked before multiplying, so a huge value can't wrap around into a small allocation.
- **Never overwrites by accident:** output files are created in exclusive mode, which also refuses to write through a symlink. `--force` is required to replace a file.
- **File names are data:** paths are always printed with `%s`, never used as a format string, and nothing is ever passed to a shell.
- **Constant-time comparison:** fingerprints are compared without stopping at the first difference, so timing reveals nothing.
- **Bounded memory:** input is streamed in fixed chunks whatever the file size.
- **Compiler hardening:** warnings are errors (`-Wall -Wextra -Wconversion -Werror`), plus stack protection, `_FORTIFY_SOURCE`, PIE and full RELRO.
- **Verified by tools:** clean under AddressSanitizer, UndefinedBehaviorSanitizer, Valgrind and the Clang static analyzer.

**Known limits, stated honestly:**

- The melody is a convenience, **not a security proof**. It carries about 69 of the fingerprint's 256 bits, which is plenty to notice an accidental or careless change, but an attacker with enough computing power could craft a different file with the same tune. For anything that matters, use `--compare` or check the full hash, which use all 256 bits.
- Earprint tells you two files are identical. It cannot tell you a file is *safe*: you still need the official fingerprint from a source you trust.
- No software can promise it is 100% secure; these are the protections in place.
