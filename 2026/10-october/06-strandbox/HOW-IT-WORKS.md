# How Strandbox works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 file ──▶ split into 20-byte chunks ──▶ add a header chunk (length + checksum)
                                              │
                         every 8 chunks get 1 parity chunk (XOR of the 8)
                                              │
        each chunk:  number + scrambled data + CRC-16   = 24 bytes
                                              │
                      24 bytes ──▶ 144 trits ──▶ 144 bases   (rotating code)
                                              │
                                       FASTA text file

 decoding runs the same steps backwards, on strands in any order:
 bases ──▶ bytes ──▶ CRC ok? ──▶ sort by number ──▶ rebuild losses ──▶ file CRC ok?
```

## 2. File tour

| File | Job |
|---|---|
| `lib/Strandbox/Codec.pm` | Bytes to DNA and back, checksums, scrambling. Knows nothing about files. |
| `lib/Strandbox/Archive.pm` | Splits a file into numbered strands, adds parity, rebuilds, reads and writes FASTA. |
| `bin/strandbox` | The command line: options, safe file reading and writing, exit codes. |
| `t/strandbox.t` | 144 checks. |

### `Codec.pm`: why not just two bits per base?

There are four bases, so the obvious code is `00→A, 01→C, 10→G, 11→T`. The trouble is that a file full of zeros becomes `AAAAAAAA...`, and both the machines that write DNA and the ones that read it lose count on long runs of one base.

The **rotating code** fixes that. Write the data in base 3, so each digit (a **trit**) is 0, 1 or 2. For each trit, choose among the *three bases that differ from the previous one*:

```
previous base   trit 0   trit 1   trit 2
     A            C        G        T
     C            G        T        A
     G            T        A        C
     T            A        C        G
```

Since the previous base is never an option, a repeat is impossible. The price is density: about 1.58 bits per base in theory, and 1.33 here because each byte is stored as six trits (3⁶ = 729, the smallest power of 3 that covers 256).

### `Codec.pm`: scrambling ("whitening")

The rotating code stops repeats, but repetitive data still gives repetitive *patterns* (`CGTACGTACGTA...`) and can drift away from the ideal 50% of G and C. So before encoding, each chunk is XOR-ed with a pseudo-random byte stream generated from the chunk's number. XOR has a handy property: doing it twice with the same stream gives the original back, so the decoder just repeats the step.

### `Archive.pm`: surviving a test tube

- **Numbering.** The first two bytes of every strand are its number. Order doesn't matter any more.
- **CRC-16 per strand.** A **cyclic redundancy check** is a short fingerprint of the bytes. If a base is misread, the fingerprint almost certainly no longer matches, and the strand is discarded. A wrong strand is worse than a missing one, because missing strands can be rebuilt.
- **Parity.** For every eight chunks, a ninth is stored: the XOR of all eight. If one of the nine goes missing, XOR the eight that remain and out comes the missing one. This is exactly how RAID 5 protects hard drives.
- **Header.** Strand 0 holds the file's length (so padding can be removed) and a CRC-32 of the whole file, checked at the very end.

### `bin/strandbox`

Parses options, reads input with a size limit, and writes output safely. All the logic lives in the modules, so the tests can call it directly; the command line is tested separately by running the real program.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Oligo | A short piece of synthetic DNA, here 144 bases |
| Homopolymer | A run of the same base (`AAAA`); the main source of read errors |
| GC content | The share of bases that are G or C; labs want it near 50% |
| Trit | A base-3 digit, like a bit but with three values |
| Checksum / CRC | A short fingerprint that changes if the data changes |
| Parity | One extra block that can rebuild any single lost block |
| Erasure vs error | A strand you know is missing vs one that is silently wrong. Erasures are much easier to fix, so checksums turn errors into erasures. |
| Coverage | How many times each strand is read; more reads, more chances of a clean copy |
| FASTA | The standard text format for sequences: a `>name` line, then the letters |

### Perl features you met here
- **`use strict; use warnings;`**: turns typos and sloppy code into errors. Every file starts with it.
- **`pack` / `unpack`**: convert between numbers and raw bytes (`'n'` is a 16-bit big-endian number, `'C*'` a list of bytes).
- **String XOR**: `$a ^ $b` on two strings XORs them byte by byte, which makes parity a one-liner.
- **Hashes of arrays** (`%NEXT`) for the code table, and a reversed hash (`%TRIT`) built from it so the two can never disagree.
- **Regular expressions** for validation (`/[^ACGT]/`) and for finding runs (`/((.)\2*)/g`).
- **Modules and `Exporter`**: `package`, `use`, and choosing which functions to share.
- **Three-argument `open` and `sysopen`**: the safe ways to open files.
- **`eval { ... }` with `die`**: Perl's try/catch. (Block `eval` is safe; *string* `eval` runs text as code and is never used here.)
- **`Test::More` and `prove`**: Perl's standard testing tools.

## 4. Interview questions you might get

**Q: Why can't the same base appear twice in your encoding?**
A: I encode in base 3 instead of base 4. Each trit selects one of the three bases that are different from the previous base, using a rotation table. The previous base simply isn't one of the choices, so repeats are impossible by construction, whatever the data is. It costs some density, which I measured: 1.33 bits per base instead of 2.

**Q: A strand comes back with one wrong base. What happens?**
A: Its CRC-16 no longer matches, so the strand is discarded rather than trusted. That turns a silent error into a known gap. If another read of the same strand is clean, that copy is used. If not, the parity strand for its group rebuilds it by XOR. Finally a CRC-32 over the whole file confirms the result. A test changes one random base 300 times and checks the file is recovered every time.

**Q: What are the limits of your error handling?**
A: Parity rebuilds one loss per group of nine, so two losses in the same group are fatal, and the program reports exactly which strands are missing. It handles substitutions and missing strands but not inserted or deleted bases, which shift everything after them. And CRCs only catch accidents: they are not cryptographic, so they don't protect against someone tampering on purpose. Production systems use Reed-Solomon or fountain codes for stronger recovery.

## 5. Ideas to extend it yourself

1. **Stronger recovery:** replace the single parity strand with Reed-Solomon coding so several losses per group can be repaired.
2. **Consensus reads:** when several damaged copies of a strand exist, take a majority vote base by base instead of waiting for one clean copy.
3. **Primers and addressing:** add fixed sequences to both ends of every strand, the way labs do, so one file can be picked out of a tube that holds many.
