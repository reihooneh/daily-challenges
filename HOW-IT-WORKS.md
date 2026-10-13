# How Inkvault works

A walkthrough so you can explain every part of it: what happens when you make a page, what happens when a camera reads one, and why each piece is there.

## 1. The big picture

```
MAKING A PAGE                                   READING A PAGE
-------------                                   --------------
text or file                                    photo (camera frame or file)
  │ packItem()       kind, name, data             │ grayFrom()        scale to ≤1600 px, grey
  │ deflate          smaller, if it helps         │ threshold()       dark = darker than its neighbourhood
  │ AES-256-GCM      only with a passphrase       │ find_candidates() 1:1:3:1:1 corner squares
  ▼                                               │ make_quad()       the 4 that make the biggest shape
iv_encode()          (C, in WebAssembly)          │ solve_homography() page cells → photo pixels
  │ header + CRC-32                               │ read_page()       9 votes per cell; split votes = doubtful
  │ 8 × Reed-Solomon (96 data + 40 check)         │                   × 8 ways (4 rotations × mirror)
  │ interleave → shuffle → mask                   │ repair_block()    errors, then errors + erasures
  │ one byte = 4 × 2 tile of cells                │ header + CRC-32   is it really ours, and intact?
  ▼                                               ▼
80 × 112 cells + 4 corner squares → SVG        open()  unlock, inflate, show as text
```

## 2. File tour

| File | Job |
|---|---|
| `core/inkvault.h` | Page geometry, error codes and the C interface |
| `core/rs.c` | Reed-Solomon over GF(256): encoding, and decoding with errors and erasures |
| `core/layout.c` | Payload → blocks → interleave → shuffle → mask → cells, and back |
| `core/scan.c` | Photo → threshold → corner squares → homography → cells |
| `core/util.c` | `memset`, `memcpy` and CRC-32, because the WebAssembly build has no C library |
| `core/wasm.c` | The WebAssembly interface: fixed buffers and a few exported functions |
| `web/codec.js` | What goes inside a page: packing, compression, encryption |
| `web/core.js` | Loads the WebAssembly and wraps it in a small, safe JavaScript API |
| `web/page.js` | Draws pages (SVG for print, canvas for images) and fakes photos for the Damage lab |
| `web/app.js` | The user interface |
| `tests/test_core.c` | C tests: Reed-Solomon, layout, and simulated photos |
| `tests/fuzz_decode.c` | Random inputs into every decoder (a libFuzzer target and a plain driver) |
| `tests/web/codec.test.mjs` | JavaScript unit tests, including end to end through the WebAssembly |
| `tests/ui-tests.mjs` | Playwright: the real page, desktop and phone, print layout, hostile input |

## 3. Key ideas, explained simply

### Reed-Solomon: maths that repairs damage
Treat each block's 96 bytes as the coefficients of a polynomial, and add 40 check bytes so that the whole 136-byte codeword is divisible by a fixed *generator* polynomial. The generator has 40 known roots: α⁰, α¹, … α³⁹.

Reading the block back, we evaluate the codeword at those 40 roots. These values are the **syndromes**. If every syndrome is zero, nothing is wrong. Otherwise the syndromes encode *where* the errors are and *how big* they are:

1. **Berlekamp-Massey** finds the shortest *error-locator polynomial* that explains the syndromes.
2. A **Chien search** tries every position to find that polynomial's roots, which are the error positions.
3. **Forney's formula** gives the value to XOR at each position.
4. The syndromes are recomputed; if they're not all zero now, the repair is refused.

All the arithmetic happens in **GF(256)**, a "finite field" of 256 elements where adding is XOR and multiplying uses log and antilog tables. That means every byte value has an inverse, so division always works.

With 40 check bytes you can fix 20 unknown errors per block. If you already know which bytes are suspect (**erasures**), each one costs only one check byte instead of two: the rule is `2 × errors + erasures ≤ 40`. The camera tells us which cells were hard to read, so a heavily damaged page can still be repaired.

### Spreading the damage
A coffee stain hits one area of the page. If one block's bytes sat together, that block would get all the damage and fail. So the 8 blocks are **interleaved** (byte 0 of block 0, byte 0 of block 1, …), and the stream is **shuffled** across the page with a fixed Fisher-Yates permutation. A stain then costs a few bytes from every block instead of many from one. Each byte stays in one compact 4 × 2 tile, so a stain damages few bytes, not many bits of many bytes.

Each byte is also XORed with a fixed pseudo-random **mask**. Without it, an empty or repetitive payload would print as big flat areas, which confuse the threshold step.

### Finding the page in a photo
- **Adaptive threshold:** a pixel is "dark" if it is at least 15% darker than the average of the square around it. An *integral image* makes every one of those averages cost four lookups, whatever the window size. Shadows, stains and uneven light shift the average too, so they mostly cancel out.
- **Corner squares:** like a QR code's, each corner is a 7 × 7 square ring with a 3 × 3 centre, so any line through its middle crosses dark-light-dark-light-dark in the ratio **1:1:3:1:1**. That ratio is the same at any size, rotation or viewing angle. The scanner looks for it along every row, then confirms it vertically and horizontally. Real corners are confirmed on many rows, while false matches in the data rarely are.
- **Which four?** Among the best-confirmed candidates, it tries each set of four with similar cell sizes that forms a convex shape, largest area first.

### From the photo back to cells: a homography
A flat page photographed from any angle is related to the original by a **homography**: a 3 × 3 matrix mapping page coordinates (u, v) to photo coordinates (x, y), division included, which is what makes far things smaller. Four point pairs (the corner-square centres) give eight equations, solved by Gaussian elimination. Then every cell centre maps to a pixel. Nine samples near each centre vote on its colour. A close vote (anything from 3-6 to 6-3) marks the cell as *doubtful*, and bytes with doubtful cells become candidate erasures.

We don't know which corner is the top-left, or whether the photo is mirrored, so all **8 assignments** are tried. Only the right one gets past Reed-Solomon and the CRC.

### Two layers of "is this right?"
Reed-Solomon can be *fooled* when there is more damage than it can handle: it may "repair" into a different valid codeword. So the header carries a magic number, a version, the length and a **CRC-32** of the payload, and the reader only accepts a page that passes all of them. With a passphrase, AES-GCM's authentication tag is a third check. The tests prove that pages damaged beyond repair are refused, not misread.

### Encryption, without inventing any
`seal()` derives a 256-bit key from the passphrase with **PBKDF2-SHA-256** (600,000 rounds, random 16-byte salt). It then encrypts with **AES-GCM** (random 12-byte IV) and binds the version and flags as *additional authenticated data*, so flipping the "compressed" flag is also detected. All of this is the browser's Web Crypto API. Compression happens *before* encryption, because encrypted data looks random and can't be compressed.

### The WebAssembly boundary
The C core is **freestanding**: no C library, no `malloc`, no imports. JavaScript asks for pointers to fixed buffers, copies bytes in, calls `encode` or `decode_image`, and copies the result out. The module literally cannot reach the network, the page or your files, and its memory can't grow. `scripts/check-wasm.mjs` checks this in CI. The same C files compile natively for the tests, under AddressSanitizer and UBSan.

## 4. Trade-offs

| Decision | Why | Cost |
|---|---|---|
| 80 × 112 cells, 2 mm each when printed | Readable by an ordinary phone at arm's length | 758 bytes per page |
| 40 of 136 bytes for checking (29%) | Survives real stains and tears | Less room for data |
| 4 corner squares, no alignment marks | Simple and robust for flat paper | Strongly curled pages may fail (roadmap) |
| C core, not JavaScript | Fast, predictable memory, testable with sanitizers | A C toolchain to build it |
| Web Crypto, not a library | Audited, built in, no dependency | PBKDF2 rather than a memory-hard function like Argon2 |
| Static page, no server | Nothing to breach, nothing uploaded | No syncing or sharing (on purpose) |

## 5. Glossary

| Term | Plain version |
|---|---|
| Error correction | Extra data that lets you rebuild damaged data |
| Erasure | A damaged spot whose position you already know |
| GF(256) | Arithmetic on bytes where every division works; adding is XOR |
| Syndrome | A value that is zero when nothing is wrong, and points at the damage when something is |
| Homography | The maths of perspective: how a flat page looks from an angle |
| Adaptive threshold | Deciding dark or light by comparing with the neighbourhood, not a fixed level |
| PBKDF2 | Deliberately slow hashing that turns a passphrase into a key |
| AES-GCM | Encryption that also detects tampering |
| Freestanding C | C without the standard library, for places like WebAssembly |

## 6. Interview questions you might get

**Q: How much damage can a page survive, and how do you know?**
A: Each of the 8 blocks has 40 check bytes, so it can fix 20 unknown bad bytes, or more when the camera marks doubtful cells as erasures (2 × errors + erasures ≤ 40). Interleaving and the shuffle spread a local stain across all blocks. I don't just assert it: the C tests render pages, simulate photos with rotation, perspective, blur, noise, shadow, stains, ink blots, tears and lens distortion, and read them back. They print how many bytes were repaired and how close each block came to failing.

**Q: What stops a damaged page from decoding to the wrong secret?**
A: Three layers. Reed-Solomon re-checks its own repair by recomputing the syndromes. Then the header's magic number, length and CRC-32 must match. And for locked pages, AES-GCM's tag must verify. Reed-Solomon alone can miscorrect past its limit, and the test suite measures that happening, but over 600 heavily damaged pages and many random images nothing wrong was ever accepted.

**Q: How do you find the page, whatever angle it's at?**
A: Adaptive thresholding makes the image black and white despite shadows. The corner squares have a 1:1:3:1:1 pattern that survives scale, rotation and perspective, so I scan rows for it and confirm vertically. Four corners give a homography. Since I don't know the orientation, I try all four rotations, mirrored and not, and let the error correction and CRC say which one is right.

**Q: Why C compiled to WebAssembly instead of JavaScript?**
A: Three reasons. The pixel and finite-field loops are fast and predictable in C. The core runs in a sandbox with no imports and fixed memory, which is a strong security boundary for code that parses untrusted photos. And I can test exactly the same code natively under AddressSanitizer, UBSan and a fuzzer, which isn't possible for JavaScript.

**Q: Is the encryption actually secure?**
A: It's the browser's Web Crypto: AES-256-GCM with a random salt and IV for every page, and PBKDF2-SHA-256 with 600,000 rounds, which is the current OWASP figure. The real risk is a weak passphrase, because whoever holds the paper can guess offline. So the page shows a strength estimate and offers a generated 100-bit passphrase. Argon2 would resist GPU guessing better, but it isn't in Web Crypto. Adding it means a dependency, which I'd weigh in a future version.

## 7. Ideas to extend it

1. **Multi-page, any-k-of-n:** add a Reed-Solomon code *across* pages, so a backup on three sheets survives losing any one.
2. **Shamir secret sharing:** split a secret into pages for different people. Any two of three can restore it; one alone learns nothing, by information theory and not just computation.
3. **Alignment marks and a mesh warp:** add small markers through the page and use a separate homography for each region, to read curled or folded paper.
