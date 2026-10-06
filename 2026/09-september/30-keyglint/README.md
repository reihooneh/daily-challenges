# Keyglint 🔑

**Catch the glint of a leaked key before it reaches Git.**

Keyglint is a fast, zero-dependency command-line tool written in Rust that scans your code for leaked secrets: cloud keys, API tokens, passwords and private keys. It masks everything it finds, so its reports are safe to paste into a chat or CI log.

## Why

Accidentally committing an API key is one of the most common security mistakes, and bots scan public GitHub for new keys within minutes. Keyglint is a small, readable scanner you can run before every push.

## Features

- **Known key shapes:** AWS access keys, GitHub tokens (classic and fine-grained), Slack tokens, Stripe live keys, and private key headers
- **Named secrets:** values assigned to things like `password`, `api_key`, `token` or `secret`, in Python, JS, JSON, YAML, Go and `.env` styles
- **Randomness detection:** uses Shannon entropy to spot random-looking strings that have no known prefix
- **Smart skipping:** ignores placeholders (`changeme`, `<your-api-key>`, `${VAR}`), binary files, huge files, and folders like `.git`, `node_modules` and `target`
- **Safe output:** secrets are always masked (`AKIA************`), never printed in full
- **CI-friendly:** exit code `1` when secrets are found, `--json` output, and `--min-severity` filtering
- **Per-line opt-out:** add `keyglint:ignore` to a line with a known-safe test value

## Example

```text
$ keyglint app
LOW     app/.env:1:15  high-entropy-string   q8Vz************
HIGH    app/settings.py:3:22  aws-access-key        AKIA************
MEDIUM  app/settings.py:4:16  named-secret          Tr0u********

✗ 3 findings (1 high, 1 medium, 1 low) in 2 files scanned.
```

```text
$ keyglint app --min-severity high --json
{"files_scanned":2,"findings":[{"path":"app/settings.py","line":3,"column":22,"rule":"aws-access-key","severity":"high","masked":"AKIA************"}]}
```

In that example, `API_KEY = "<your-api-key>"` and `GREETING="hello there"` were correctly left alone.

## Tech

Rust 2021, standard library only (no crates), `cargo test` for tests.

## Install and run

```bash
cd 2026/09-september/30-keyglint
cargo build --release
./target/release/keyglint path/to/your/project
```

Or run it straight from source: `cargo run -- path/to/scan`.

### Options

| Option | What it does |
|---|---|
| `--json` | Machine-readable output |
| `--min-severity low\|medium\|high` | Hide findings below a level |
| `-h`, `--help` | Show help |
| `-V`, `--version` | Show version |

| Exit code | Meaning |
|---|---|
| `0` | No secrets found |
| `1` | Secrets found |
| `2` | Bad option or unreadable path |

### Use it as a Git pre-commit hook

```bash
# .git/hooks/pre-commit
#!/bin/sh
keyglint . --min-severity medium || { echo "Commit blocked: remove the secrets above."; exit 1; }
```

## Tests

```bash
cargo test
```

14 tests cover entropy, masking, every rule, word boundaries, placeholders, the ignore marker, line and column numbers, and the CLI (folder skipping, JSON output, exit codes, and a check that raw secrets are never printed).

## Security

Keyglint reads files it knows nothing about, and its whole job is handling secrets, so it is careful with both.

- **Secrets are never printed in full.** Every finding is masked before it reaches the screen or the JSON output, and a test checks that no raw secret appears in either.
- **Bounded reading.** Files over 1 MB and binary files are skipped, so a huge or odd file can't exhaust memory.
- **Symbolic links are not followed,** so a link inside a project can't lead the scan to files outside it.
- **Read-only.** It never changes, deletes or uploads anything, and makes no network connections.
- **Safe Rust, no dependencies.** There is no `unsafe` code and nothing third-party to trust.

**Known limits:** it can't prove a project is free of secrets (see Limitations below), and no software can promise it is 100% secure.

## Limitations

Keyglint uses rules and entropy, so it can miss unusual secrets and occasionally flag a random-looking value that isn't secret. It's a safety net, not a guarantee. If a real key ever leaks, **revoke it with the provider**: deleting the commit is not enough.
