# Commadrift

**Tunes a chord progression so every chord rings pure, while notes held from one chord to the next barely move, and shows how far the music would drift if they couldn't move at all.**

Language: C11 (standard library only) · Field: music acoustics / numerical linear algebra · Day: 20 October 2026

Pianos use equal temperament: every semitone is exactly 100 cents. That's a compromise. A *pure* major third (frequency ratio 5:4) is 13.7 cents lower than the piano's, which is why chords on a piano shimmer, or "beat". Choirs, string quartets and barbershop singers tune chords pure by ear.

But tuning every chord pure has a catch. When a singer holds a note from one chord into the next, the pure tunings of the two chords often disagree about where that note should be. Insist the held note stays still and the pitch slowly slides: after C – Am – Dm – G – C the choir ends **21.5 cents (a syntonic comma) flat**. That's the famous *comma pump*.

Commadrift works out a plan: every chord pure, held notes moving as little as possible, and the piece kept near concert pitch. The balance is yours to choose.

## Quick start

```bash
make
./commadrift examples/comma-pump.txt
make test          # unit and command-line tests, with AddressSanitizer and UBSan
make analyze       # GCC's static analyser
```

```
COMMADRIFT  comma-pump.txt  (5 chords, A4 = 440 Hz)

If every chord is pure and held notes never move, the music ends 21.5 cents lower than it
started (exactly a syntonic comma, 81/80).

Balanced plan (glide weight 1, drift weight 1): cents from equal temperament
    1  C maj      C4     +7.9 E4     -5.8 G4     +9.9
    2  A min      A3     -3.8 C4    +11.9 E4     -1.8
    3  D min      A3     +0.4 D4     -1.6 F4    +14.0
    4  G maj      G3     -1.0 B3    -14.7 D4     +0.9
    5  C maj      G3     +0.5 C4     -1.5 E4    -15.2

Largest glide of a held note: 4.1 cents (A3, from chord 2 to 3): hard to hear
The last chord ends -9.4 cents from where the first began (strict plan: -21.5).
```

Each number is how far that note should sit from the piano's pitch, in cents (hundredths of a semitone). `--hz` adds the frequency of every note.

## The progression file

```
a4 440                       # reference pitch (optional)
weights glide 1 drift 1      # optional: bigger glide = held notes stiller; bigger drift = closer to concert pitch
C4 E4 G4                     # one chord per line
A3 C4 E4
```

It recognises major, minor, dominant 7th (with the pure 7:4 seventh), major 7th, minor 7th, sus4 and diminished chords, plus fifths, thirds and single notes, in any inversion. A note counts as "held" when the same note (same octave) is in both chords. Exit codes: `0` done, `2` bad input.

## Security

- **Bounded input:** at most 16 KB, 120 characters a line, 256 chords and 6 notes a chord. Only regular files are opened, with `O_NOFOLLOW` (no symlinks), so `/dev/zero`, pipes and directories are refused; reading stops at the limit.
- **Strict text:** only printable ASCII is accepted, so terminal escape codes and hidden Unicode direction marks are refused. Numbers must be plain decimals in range (no `nan`, no `1e9`). Errors give a line number and never repeat the input, and file names are cleaned before printing.
- **Memory safety in C:** fixed-size buffers with explicit bounds checks, `snprintf` everywhere, no dynamic allocation. The tests run under **AddressSanitizer and UndefinedBehaviorSanitizer**, the build uses `-Wall -Wextra -Wconversion -Werror`, `_FORTIFY_SOURCE` and stack protection, and GCC's `-fanalyzer` reports nothing.

**Known limits:** it tunes chords as written; it doesn't guess chords from melody, and notes held in a different octave don't count as held. "Pure" means simple ratios, one standard choice per chord type; musicians sometimes prefer others (for example a 16:9 minor seventh instead of 7:4).

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
