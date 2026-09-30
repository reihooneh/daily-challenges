# How Keyglint works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
main.rs  (the CLI)                       lib.rs  (the brain)
────────────────────                     ───────────────────
read arguments                           scan_text(path, text)
walk folders, skip junk      ──text──▶     for each line:
read each file as text                        known-shape rules
filter by severity           ◀─findings─      quoted-value rules
print human or JSON output                  mask(), shannon_entropy()
exit 0 / 1 / 2
```

The key design decision is that **`lib.rs` is pure**: it takes a string and returns findings, with no files, printing or exiting. That makes it easy to test (most tests just call `scan_text`) and easy to reuse later, for example in a web version.

## 2. File tour

### `src/lib.rs`
- **`Severity`**: an enum (`Low`, `Medium`, `High`). Because it derives `PartialOrd`/`Ord`, you can compare levels with `>=`, which is how `--min-severity` works.
- **`shannon_entropy`**: counts how often each character appears and computes `−Σ p·log₂(p)`. The result is "bits of surprise per character": `aaaa` scores 0, English is about 3, random keys are 4.5 to 6.
- **`mask`**: keeps the first 4 characters and stars out the rest, so the tool never leaks what it finds.
- **`find_prefixed`**: a tiny hand-written matcher. It looks for a prefix like `AKIA`, checks there's no letter glued in front (a *word boundary*), then counts allowed characters after it. This replaces a regex library.
- **`quoted_strings` / `assigned_name`**: pull out every `"..."`, `'...'` or `` `...` `` value, and work out the variable name on the left of `=`, `:`, `:=` or `=>`.
- **`scan_text`**: runs every rule on every line, skips lines with `keyglint:ignore`, and avoids reporting the same value twice.

### `src/main.rs`
- **`parse_args`**: a small hand-rolled argument parser (no `clap` crate).
- **`collect`**: walks folders recursively and skips `.git`, `node_modules`, `target` and similar.
- **`read_text`**: skips files over 1 MB, and treats a file as binary if its first 8,000 bytes contain a zero byte (the same trick Git uses).
- **Output**: human-readable lines or JSON, then an exit code for CI.

### `tests/scan.rs`
Integration tests for the library plus a full CLI test that runs the real compiled binary (`env!("CARGO_BIN_EXE_keyglint")`) on a temporary folder.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Shannon entropy | A number for "how random is this text?" |
| Word boundary | Only match `AKIA...` when it isn't part of a longer word |
| False positive / negative | Flagging something harmless / missing a real secret. Entropy thresholds balance the two |
| Exit codes | How command-line tools report success or failure to scripts and CI |
| Masking | Showing just enough to recognise a secret without exposing it |

### Rust features you met here
- **Ownership and borrowing.** An early version used a closure that *mutably* borrowed the `hits` list, then tried to read `hits` while that borrow was still alive. Rust refused to compile it (error E0502). The fix was a closure that only *builds* a `Finding`, and pushing it separately. This is Rust stopping a whole class of bugs at compile time.
- **Enums with derived traits** (`#[derive(PartialOrd, Ord)]`) for free comparisons.
- **`Option` and `Result`** instead of null and exceptions, e.g. `parse_args` returns `Result<Option<Options>, String>`.
- **Iterators**: `.iter().filter().map().collect()` chains throughout.
- **`ExitCode`** to return proper exit statuses from `main`.

### A neat testing trick
The tests build fake tokens at runtime, like `format!("{}{}", "ghp_", "a1B2".repeat(9))`, instead of writing them out in full. GitHub scans pushes for real-looking tokens and would block a file containing them, so this keeps the tests pushable.

## 4. Interview questions you might get

**Q: How do you detect a secret that has no known prefix?**
A: With Shannon entropy. Random strings have high entropy per character. I only check long values made of base64 or hex characters, with a lower threshold for hex (only 16 possible characters) than base64 (64 characters).

**Q: How do you avoid false positives?**
A: Word boundaries on prefixes, a minimum length, a placeholder list (`changeme`, `${VAR}`, `<...>`), skipping dependency and build folders, an ignore marker, and severity levels so people can filter out the "probably fine" low findings.

**Q: Why no regex library?**
A: The patterns are simple prefixes plus character classes, so a small hand-written matcher is enough, keeps the binary dependency-free, and makes the matching logic easy to read and test.

## 5. Ideas to extend it yourself

1. **Scan Git history:** secrets deleted in a later commit still exist in old commits. Try reading `git log -p` output.
2. **A config file** (`.keyglint.toml`) for custom rules and ignored paths.
3. **Coloured output** when writing to a terminal, using ANSI escape codes.
