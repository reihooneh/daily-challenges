# How Earprint works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 file ──read in 64 kB chunks──▶ SHA-256 ──▶ 32 bytes (the fingerprint)
                                               │  2 bytes per note
                                               ▼
                                    16 notes (pitch + short/long)
                                               │
                              sine waves with a bell-like fade
                                               ▼
                                   audio samples ──▶ WAV file
```

Each stage is its own small module with no knowledge of the others:

| File | Job |
|---|---|
| `sha256.c` | The hash function, plus hex output and safe comparison |
| `melody.c` | Fingerprint → notes → audio samples |
| `wav.c` | Wraps samples in a valid WAV file |
| `main.c` | Command line: reads files, prints results, sets exit codes |
| `tests/` | C unit tests and a shell script that runs the real program |

## 2. File tour

### `sha256.c`: the hash
A hash function turns any amount of data into a fixed 32-byte fingerprint. Change one bit of the input and about half the output bits flip.

- **Blocks:** data is processed 64 bytes at a time. `sha256_update` collects bytes in a buffer and calls `compress` whenever the buffer is full.
- **`compress`:** stretches the 64 bytes into 64 words, then runs 64 rounds that scramble eight state variables using rotations, XORs and additions.
- **Padding (`sha256_final`):** the message must end on a block boundary, so a `1` bit, some zeros, and the message length are appended. If there's no room for the length, an extra block is added. This is the classic place for bugs, which is why the tests hammer lengths 55, 56, 63, 64 and 65.
- **`sha256_equal`:** compares two fingerprints without stopping at the first difference (see "timing attack" below).

### `melody.c`: fingerprint to music
- Each note takes two bytes: `pitch = byte1 % 10` picks one of ten notes, and the lowest bit of `byte2` chooses short or long.
- The notes are a **pentatonic scale** (C D E G A). It has no clashing intervals, so *any* random sequence sounds musical.
- **Sound:** a note is a sine wave at the note's frequency, plus two quieter waves at 2× and 3× that frequency (overtones) for a richer tone. An *envelope* shapes the volume: a 5 ms fade-in, a bell-like decay, and a 10 ms fade-out so there are no clicks.

### `wav.c`: the audio file
A WAV file is a 44-byte header (format, sample rate, data size) followed by raw samples. Numbers are written one byte at a time in little-endian order, so the file is correct on any kind of CPU.

### `main.c`: the program
Parses options, hashes files in chunks, prints the fingerprint and melody, and optionally saves the WAV.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Hash / fingerprint | A short value that changes completely if the data changes at all |
| Buffer overflow | Writing past the end of an array; the most famous C security bug |
| Integer overflow | A number wrapping around to a small value after getting too big |
| Timing attack | Learning a secret by measuring how long a comparison takes |
| Format-string bug | Passing user text as the format to `printf`, letting `%n` and friends do damage |
| Sanitizers | Compiler tools that stop the program the instant it touches memory it shouldn't |

### C features you met here
- **Header files (`.h`)** declare what a module offers; `.c` files contain the code. Include guards (`#ifndef ...`) stop double inclusion.
- **Fixed-width integers** (`uint8_t`, `uint32_t`, `uint64_t`) so sizes are the same on every machine. SHA-256 depends on exact 32-bit wraparound.
- **`static`** functions and tables are private to their file.
- **`size_t`** for sizes and counts, never `int`.
- **Explicit casts** with `-Wconversion`: the compiler flags every place a value might be silently truncated.
- **`snprintf`** instead of `sprintf`: you tell it the buffer size and it never writes past it.
- **Exclusive file creation:** the `"wbx"` mode makes `fopen` fail if the file exists.
- **A `Makefile`** with a normal build and a separate sanitizer build for tests.

### Why "refuse" instead of "truncate"
Functions like `melody_render` and `melody_to_text` take the buffer's size and return an error if it's too small, leaving the buffer untouched. Quietly truncating can hide bugs; refusing makes them obvious.

## 4. Interview questions you might get

**Q: You wrote your own SHA-256. How do you know it's correct?**
A: I test it against NIST's official vectors, including a one-million-character input, check that feeding data in odd-sized pieces gives the same result as one call (this covers every padding edge case), and compare it with the system's `sha256sum` on random files. For real products I'd use an audited library; writing it here was to learn how it works.

**Q: What is a timing attack, and how does your comparison avoid it?**
A: If a comparison returns at the first mismatched byte, the time taken leaks how many leading bytes were right, and an attacker can guess a secret byte by byte. My version ORs together the differences of all 32 bytes and only checks the result at the end, so it always takes the same time.

**Q: C has no bounds checking. What did you do about memory safety?**
A: Three layers. Design: fixed maximum sizes, length-checked copies, overflow checks before multiplying, and functions that refuse small buffers. Compiler: warnings as errors and hardening flags. Testing: every test runs under AddressSanitizer and UndefinedBehaviorSanitizer, plus Valgrind and a static analyzer, with deliberately hostile inputs.

## 5. Ideas to extend it yourself

1. **Use all 256 bits:** play two melodies at once (melody plus bass line) or 32 notes, so the tune carries more of the fingerprint.
2. **Read from standard input** (`earprint -`) so it works in pipelines like `curl ... | earprint -`.
3. **Play directly** through the sound card instead of saving a file, or export MIDI.
