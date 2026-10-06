# Security

Pick Two is a static web page plus a command-line tool. It has no server, no accounts and no database, so the attack surface is small. This document lists what an attacker could try and what stops them.

No software can be guaranteed 100% secure. What follows is the design, the tests behind it, and the limits I know about.

## What is worth protecting

| Asset | Why it matters |
|---|---|
| The user's browser session | A page that runs injected script could do anything the user can do on that origin |
| The user's timetable | It reveals where a person will be, and when |
| The user's device | A planner that can be made to spin forever is a denial of service |
| The user's terminal (CLI) | Printed text can carry escape codes that rewrite the screen |

## Threat model

| An attacker might... | Defence | Tested by |
|---|---|---|
| Put HTML or script in a course title or note, hoping the page renders it (XSS) | The page never uses `innerHTML` or similar; all text goes through `textContent`. The parser also allow-lists characters in titles and notes. A strict Content-Security-Policy blocks inline and third-party script as a second layer. | `TestParseRejectsHostileTextWithoutEchoingIt`, browser check step 5 |
| Send a victim a crafted share link | The part after `#` must be base64url, at most 16,000 characters, valid UTF-8 and valid JSON. The state is then rebuilt field by field with type and range checks; unknown keys (including `__proto__`) are dropped. A link that fails is discarded and removed from the address bar. | `state.test.js` (hostile links, untrusted state), browser check step 6 |
| Paste input designed to make the solver run forever | Input is capped (64 kB, 12 courses, 6 components, 30 options, 24 wishes). The solver counts its steps and stops at a fixed budget: 2 million for the main search, 6 million for explanations. In the browser it runs in a Web Worker that is terminated after 20 seconds as a backstop. | `TestWorstCaseInputFinishesInBoundedTime`, `TestNodeLimitIsRespected` |
| Use a slow regular expression (ReDoS) | Parsing uses Go's `regexp` package, which guarantees linear-time matching. The JavaScript side uses only anchored, non-nested patterns. | Fuzzing (640,000 runs locally, 30 s on every CI run) |
| Crash the planner with malformed input | The parser returns errors as values. The WebAssembly entry point recovers from panics and returns an error object. A fuzz test asserts that any input produces one of four known statuses. | `FuzzRun`, `wasm.test.js` |
| Hide terminal escape codes in a file given to the CLI | Any control or invisible formatting character is rejected before parsing, and error messages contain line numbers, never input. | `TestParseRejectsHostileTextWithoutEchoingIt` |
| Make the CLI read something it shouldn't | It opens only the single path given, only if it is a regular file, and reads at most 64 kB + 1 byte. It never writes files or runs commands. | `TestUnreadableInputs` |
| Exfiltrate a timetable | The page makes no network requests except loading its own files (`connect-src 'self'`), sets no cookies and uses no storage. A plan leaves the device only if the user copies a share link. | CSP in `index.html`; browser check asserts zero console errors under that policy |
| Compromise a dependency | The Go module has zero dependencies. The only third-party code in the site is `wasm_exec.js`, the loader shipped with the Go toolchain, copied in at build time. | `go.mod`, `Makefile` |
| Abuse the build pipeline | The workflow's default token is read-only; only the deploy job gets Pages permissions, and only on `main` after tests pass. | `.github/workflows/ci.yml` |

## Known limits

- **A share link contains the whole plan.** Anyone who has the link can read it. It is in the URL fragment, which browsers don't send to servers, but it will be in browser history.
- **The Content-Security-Policy is set with a `<meta>` tag**, because GitHub Pages can't send custom headers. A meta policy can't set `frame-ancestors`, so the page doesn't forbid being framed. It has no logged-in state to click-jack, which keeps that risk low.
- **`'wasm-unsafe-eval'` is in the policy.** Browsers require it to compile WebAssembly. It does not allow JavaScript `eval`.
- **GitHub Actions are pinned by version tag, not commit hash.** Pinning to hashes would be stricter.
- **Budgets mean "unknown" is a possible answer.** On a very large timetable the planner may stop and say it couldn't finish, and an explanation may be marked incomplete. It never presents an unfinished search as a definite "impossible".
- The planner's output is only as good as the class times typed in. Always confirm with your university.

## Reporting a problem

Please open a GitHub issue on this repository. If the problem is sensitive, use GitHub's "Report a vulnerability" button under the Security tab so it stays private until fixed. I aim to reply within a week.
