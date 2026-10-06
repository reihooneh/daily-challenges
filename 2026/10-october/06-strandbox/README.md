# Strandbox 🧬

**Store a file as DNA, damage it, and get it back.**

DNA is the densest and longest-lasting storage medium we know of: a mammoth genome has been read after a million years in permafrost. Strandbox turns any small file into DNA sequences you could send to a synthesis lab, and rebuilds the file from whatever strands come back, in any order, even when some are lost or misread.

## What makes it different

Simple "file to DNA" converters map two bits to each base and stop there. That produces DNA that can't be made or read reliably, and the file is gone if a single strand is lost. Strandbox is small enough to read in one sitting but deals with the problems real DNA storage has:

- **No repeated bases, ever.** Sequencers make most of their mistakes on runs like `AAAA`. Strandbox uses a rotating code in which the same base can never appear twice in a row.
- **Balanced composition.** Data is scrambled with a fixed pattern first, so even a file full of zeros comes out as about 50% G and C, which is what synthesis needs.
- **Strands have no order.** A test tube is a soup. Every strand carries its own number, so the pool can be shuffled.
- **Every strand checks itself.** A checksum on each strand catches any misread base, so a damaged strand is thrown out instead of corrupting the file.
- **Lost strands are rebuilt.** Each group of eight strands gets a ninth "parity" strand. Lose any one of the nine and it is recalculated from the rest.
- **A built-in time machine.** `strandbox damage` simulates loss and read errors so you can watch recovery work, or fail.

## Example

```text
$ strandbox encode examples/message.txt -o message.fasta
Stored 169 bytes in 12 oligos (1728 bases). GC 50%, longest repeat 1.

$ head -2 message.fasta
>oligo_00001
CGTACGTACGTACGTCAGTATACGTACACTATCACGTATAGACAGACACACTGCGCTGATATGCACGACTCG...

$ strandbox damage message.fasta --seed 3 -o aged.fasta
12 strands in, 32 reads out (3 reads of each, some lost).

$ strandbox decode aged.fasta
Read 32 strands: 0 damaged, 20 duplicate, 0 rebuilt from parity.
Rebuilt 169 bytes. Checksum matches.
DNA keeps information for a very long time.
A mammoth genome was read after more than a million years in permafrost.
This note fits in twelve strands of 144 bases each.
```

("Oligo" is the lab word for a short, synthetic strand of DNA.)

## Commands

| Command | What it does |
|---|---|
| `strandbox encode FILE [-o OUT.fasta]` | Store a file (up to 256 kB) as DNA in FASTA format |
| `strandbox decode FASTA [-o OUT]` | Rebuild the file; reports damaged, duplicate and rebuilt strands |
| `strandbox stats FASTA` | Base balance, longest repeat, size |
| `strandbox damage FASTA [--loss P] [--errors P] [--copies N] [--seed N]` | Simulate lost strands and misread bases |

Use `-` to read standard input. Exit codes: `0` success, `1` the file could not be rebuilt, `2` bad input or usage.

## How well does it survive?

Measured on the example file, 200 simulated runs each, with 5% of reads lost and 0.1% of bases misread:

| Reads of each strand | Files rebuilt correctly |
|---|---|
| 3 (the default) | 200 of 200 |
| 1 | about half |

In every failed run the program said so. In the tests it never once returned a wrong file.

## Tech

Perl 5 (tested on 5.38), core modules only. Nothing to install from CPAN.

## Run it

```bash
cd 2026/10-october/06-strandbox
bin/strandbox encode examples/message.txt -o /tmp/message.fasta
bin/strandbox damage /tmp/message.fasta | bin/strandbox decode -
```

## Tests

```bash
prove -l t
```

144 checks:

- **The code:** every byte value round-trips, no output ever has a repeated base, and both checksums match their published test values.
- **Whole files:** sizes on every boundary (0, 19, 20, 21, 140 bytes and so on) survive shuffling.
- **Loss and damage:** losing any single strand is survivable, including the header and the parity strands; one loss in every group is survivable; two in one group is reported with the exact missing numbers; all 300 random single-base changes are detected and repaired.
- **Hostile input:** bad FASTA, script tags, terminal escape codes, oversized files and lines, file names that look like shell commands, refusing to overwrite files or write through symlinks.

All code runs under `use strict` and `use warnings` with no warnings.

## Security

- **Input is validated letter by letter.** Sequences may contain only A, C, G, T and N. Anything else stops the program with a line number, and the offending text is never printed back, so a crafted file can't inject terminal escape codes.
- **Everything is bounded.** At most 256 kB can be stored, 16 MB of FASTA read, and 4,096 characters per line. Files are read in chunks and abandoned as soon as they pass the limit.
- **Damage is detected, not trusted.** Each strand has a CRC-16 and the whole file a CRC-32. A file that fails its checksum is never written out.
- **File names are only ever file names.** Files are opened with Perl's three-argument `open`, so a name like `| rm -rf ~` is not a command. No shell is ever invoked.
- **No accidental overwrites.** Output files are created in exclusive mode, which also refuses to write through a symbolic link. Replacing a file needs `--force`.
- **No `eval` of strings, no network, no dependencies** beyond Perl's own core modules.

**Known limits, stated honestly:**

- **Checksums are not security.** CRCs catch accidents, not attackers. Someone who can edit the strands deliberately can forge a valid file. The scrambling step is not encryption either: anyone with this program can read the data.
- **It is a learning tool, not a lab pipeline.** Real DNA storage adds primers for copying, handles inserted and deleted bases (Strandbox only handles substitutions and loss), and uses stronger codes such as Reed-Solomon or fountain codes.
- **One loss per group.** Two missing strands from the same group of nine can't be rebuilt. Reading each strand several times, as sequencers do, is what makes that rare.
- The simulator's random numbers are seeded and repeatable on purpose; they are not suitable for anything secret.
- No software can promise it is 100% secure; these are the protections in place.
