# Security

Inkvault exists to protect small, important secrets, so security is part of the design, not an afterthought. No software is perfectly secure; this page says what Inkvault defends against, how, and where its limits are.

## What it protects

| Asset | Protection |
|---|---|
| The secret on the paper | Optional passphrase: AES-256-GCM, with the key derived by PBKDF2-SHA-256 over 600,000 rounds and a random 16-byte salt. A fresh random IV is used for every page. The version and flags are bound in as authenticated data. |
| The secret while you type it, and when it's read back | Everything happens in your browser. Nothing is uploaded, and there are no accounts, analytics, trackers or third-party scripts. A Content-Security-Policy blocks every network request except loading the page's own files. |
| Your device | The decoder is C compiled to WebAssembly with **no imports**: it can only touch its own fixed-size memory, never the page, the network or your files. CI checks this on every build. |

## Threat model

| An attacker might try… | What stops them |
|---|---|
| Reading a locked page they found or photographed | AES-256-GCM. With a generated passphrase (about 100 bits), guessing is out of reach; PBKDF2 slows down attacks on weaker passphrases. |
| Changing a locked page so it decodes to something else | GCM authentication: any change makes decryption fail ("wrong passphrase, or the page was altered"). |
| Changing an unlocked page | A CRC-32 catches accidental damage, but an unlocked page is not signed, so anyone who can print can make a page that says anything. Treat unlocked pages like any piece of paper. |
| A photo built to crash the decoder or read outside memory | Every size is checked twice (JavaScript and C). Photos are capped at 1600 × 1600 pixels and 40 MB, and memory is fixed. The C code has no allocation and no recursion, and the reader caps its work. The core is tested under AddressSanitizer and UBSan, and fuzzed with random images, cell grids and Reed-Solomon codewords. It passes clang-tidy's bugprone, CERT and analyzer checks with warnings as errors. |
| A page that "decompresses" into gigabytes | Decompression is streamed and stops at 64 KB. |
| A page containing HTML or script, shown back to you | Restored text is shown with `textContent` and never parsed as HTML, so `<script>` is just text. The CSP also blocks inline scripts. Both are tested in a real browser. |
| A restored file named `../../.bashrc` or `invoice.pdf‮exe` | File names are stripped of paths, control and bidirectional characters, and length-capped. Files are only ever offered as a plain download (`application/octet-stream`), never opened. |
| Leaving the secret in memory | After a page is made or read, the WebAssembly buffers are zeroed. "Clear from screen" also drops the restored data. |

## Known limits

- **The passphrase is the key.** If it is weak and someone gets the paper, they can try guesses offline. Use **Generate**, and keep the passphrase somewhere other than the paper.
- **Browser memory:** JavaScript can't guarantee that every copy of a string is wiped. Close the tab when you're done on a shared computer.
- **The device you use must be trustworthy.** Malware or a malicious browser extension can read whatever you type into any web page.
- **Paper is physical.** Error correction helps with stains and tears, not fire or a lost envelope. Keep two copies in two places.
- **Big images:** a deliberately huge image file (a "decompression bomb") could slow your own browser tab while it decodes. It can't reach anything else.
- Unlocked pages are not signed (see above).

## Reporting a problem

Please report security issues privately to **reihaneh26686@gmail.com** with "Inkvault security" in the subject, rather than opening a public issue. Include steps to reproduce and, if possible, a sample image or page. I'll reply within a week, and I'll credit you in the fix unless you'd rather I didn't.
