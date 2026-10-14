# How Lowtide works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 november.txt ──▶ parsePlan()       start, balance, buffer, incomes, bills, spending
                      │             (money as integer cents, dates as day numbers)
                      ▼
                 occurrences()      every day each schedule falls on, inside the window
                      │
                      ▼
                 forecast()         day by day: bills out, then pay in → the low tide
                      │
                      ▼
                 optimise()         branch and bound over new due days for movable bills
                      │
                      ▼
                 render()           as it is · moves · after · charts · what's still short
```

## 2. File tour

| File | Job |
|---|---|
| `src/plan.ts` | The file format, money (cents) and dates (day numbers), with validation |
| `src/ledger.ts` | When each schedule falls, and the day-by-day forecast |
| `src/optimise.ts` | The branch-and-bound search for new due days |
| `src/report.ts` | The text report and the sparkline charts |
| `src/cli.ts` | Command line: bounded reading, safe file name, exit codes |
| `tests/lowtide.test.ts` | 11 tests, including a brute-force check of the optimiser |

## 3. Key ideas

### Money in cents, dates as numbers
`0.1 + 0.2` isn't `0.3` in floating point, so every amount is parsed straight into **whole cents** (`1,180.00` becomes `118000`) and added as integers. Dates become **day numbers**, days since 1 Jan 1970 in UTC. That makes "add 14 days" plain arithmetic and avoids time-zone and daylight-saving surprises. The tricky part is months: a bill "monthly on 31" falls on the last day of shorter months, and a quarterly bill from 30 November falls on 28 February.

### The low tide
Each day, payments leave, the balance at that moment is recorded, and then income arrives. The **low tide** is the smallest of those daily lows. Taking bills out first is the cautious assumption, because banks don't guarantee which transaction happens first.

### Choosing new due days: branch and bound
With *k* movable bills and 28 possible days each, there are 28ᵏ plans: 784 for two bills, but 377 billion for eight. Trying them all is out. The search decides bills one at a time, biggest first, and keeps two facts:

1. **The balance so far** with the decided bills placed (`current[d]`).
2. **The least each undecided bill could have taken out by each day**, whatever day it ends up on (`least`). Summed over the undecided bills, that's `rest[i][d]`.

So no completion of this branch can have a low tide higher than `min over days of (current[d] − rest[i][d])`. That's an optimistic **bound**. If even the bound can't beat the best plan found so far, the whole branch is skipped. Trying each bill's own day first, then nearby days, finds good plans early, so the bound prunes hard. Eight movable bills finish in about two million steps.

### What "best" means
The plans are compared in order: first `min(low tide, buffer)`, because once you're above the buffer, more cushion isn't worth another phone call. Then the number of bills moved, then the low tide itself, then how far the bills moved in total. Each part of a branch's bound is optimistic (the low tide can only fall, and moves can only grow), so comparing the bound with the best plan lexicographically is a safe prune.

### Trust, but verify
After the search, the chosen days are run through the ordinary `forecast()` again, an independent recomputation. The tests also brute-force every combination of days on 60 random budgets (including a bill on the 30th that may stay put) and check that the optimiser finds the same low tide and the same number of moves.

## 4. Glossary

| Term | Plain version |
|---|---|
| Low tide | The lowest your balance gets in the forecast |
| Buffer | A cushion you never want to go below |
| Branch and bound | Search a tree of choices, and skip branches that provably can't win |
| Bound | An optimistic estimate of the best a branch could do |
| Lexicographic order | Compare by the first thing, use the second only to break ties, and so on |

### TypeScript features you met here
- **Discriminated unions** (`Schedule`, with an `every` tag) and `switch` statements the compiler checks are complete.
- **`never`** as the return type of `fail()`, so TypeScript knows code after it is unreachable.
- **Strict settings:** `strict`, `noUncheckedIndexedAccess` (array reads might be `undefined`) and `exactOptionalPropertyTypes`.
- **Typed arrays** (`Float64Array`) for the hot loop.
- **Node's built-in test runner** (`node:test`), so there's no test framework to install.

## 5. Interview questions you might get

**Q: Why not just try every combination?**
A: 28 days for each bill means 28ᵏ plans: fine for two or three bills, impossible for eight. Branch and bound gives the same answer as trying everything, because it only skips branches whose optimistic bound already loses, and it usually explores a tiny fraction. The tests prove it matches brute force where brute force is feasible.

**Q: Why is the bound valid?**
A: The balance on any day is the starting money, minus everything paid out by then, plus income. For an undecided bill, the least it can have taken out by day *d* is the minimum over its possible due days. So no real choice can leave more money on day *d* than `current[d] − rest[d]`, and the minimum over days is an upper limit on the low tide.

**Q: Why prefer fewer moves over a higher low tide?**
A: Every move is a phone call or a form, and some providers charge for it. Once you're safely above your buffer, extra cushion is worth less than effort. That's a product decision written into the order of comparison, and it's easy to change.

## 6. Ideas to extend it

1. **Read a bank export** (CSV) to estimate everyday spending and detect regular bills automatically.
2. **Split payments:** suggest paying a large bill in two halves when the provider allows it.
3. **Uncertain spending:** simulate many possible months and report the chance of dipping below the buffer, not just one forecast.
