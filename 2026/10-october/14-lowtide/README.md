# Lowtide

**Finds the lowest point your bank balance will reach in the coming months, and which bill due dates to move so it never dips below your safety buffer.**

Language: TypeScript (Node, no runtime dependencies) · Field: personal finance / combinatorial optimisation · Day: 14 October 2026

Being short of money for two days a month is often a timing problem, not a money problem. Rent, the phone, insurance and the loan all come out in the week before payday, and the account dips into overdraft fees, then recovers. The usual advice is "ask your providers to move your due dates", but *which* bills, and to *which* days? Lowtide forecasts your balance day by day and finds the **low tide**. Then it searches every combination of new due days for the bills you could move, and finds the plan that keeps you above your buffer while moving **as few bills as possible**.

## Quick start

```bash
npm ci
npm test                                  # compiles, then runs the tests
node dist/src/cli.js examples/november.txt
```

```
LOWTIDE  november.txt  (91 days from Sun 1 Nov 2026; buffer $150.00)

AS IT IS
  Low tide -$125.35 on Thu 12 Nov 2026
  Below your buffer on 2 days, overdrawn on 2.
  ▂▂▂▂▂▁▃▃▃▃▃▃▃▅▅▃▃▃▃▂▄▄▄▄▅▄▄▆▆▆▅▅▄▄▆▆▅▅▆▆▆██▇▇█
       ^
  one mark per 2 days; ^ = below your buffer

MOVE THESE DUE DATES
  Phone              $55.00   from the 9th to the 13th
  Car insurance     $112.40   from the 10th to the 13th
  Student loan      $150.00   from the 8th to the 13th

AFTER
  Low tide $192.05 on Thu 12 Nov 2026: never below your buffer.
  ▂▁▁▂▂▁▃▃▂▂▃▃▃▅▅▂▂▃▃▃▅▄▄▄▄▄▄▆▆▆▄▄▄▄▆▆▅▅▆▆▆██▇▇█
  one mark per 2 days
  That's $317.40 more at the lowest point.
```

Notice that the internet bill stays on the 12th: three moves are enough, so it doesn't suggest four.

## The plan file

```
start 2026-11-01
days 91                     # how far ahead to look (7 to 400)
balance 1600.00             # today's balance
buffer 150.00               # never go below this

income Pay            1180.00 fortnightly from 2026-11-12
bill Rent             1100.00 monthly on 1 fixed
bill Phone              55.00 monthly on 9 movable
bill Electricity       265.00 quarterly from 2026-11-11
spend Groceries and transport 34.00 daily
```

Schedules: `once on DATE`, `weekly from DATE`, `fortnightly from DATE`, `monthly on DAY` (1–31, or `last`; days past the month's end fall on its last day), `quarterly from DATE`, `yearly from DATE`, `daily`. Add `movable` to the monthly bills whose due date you could change. They can be moved to the 1st–28th, because those days exist in every month.

On a day with both, the forecast assumes **bills leave before the pay arrives**. That's the cautious choice, since banks don't promise an order.

## How it decides

The search looks for, in order:

1. staying **at or above the buffer** (or as close as possible);
2. moving the **fewest bills**;
3. the **highest low tide**;
4. the **smallest moves**.

It uses branch and bound: bills are decided one at a time, biggest first. A branch is dropped as soon as even its most optimistic outcome can't beat the best plan found so far, so it doesn't need to try all 28⁸ combinations. A test compares it with brute force over every combination on 60 random budgets. Details are in [HOW-IT-WORKS.md](HOW-IT-WORKS.md).

## Security

Budgets are private, and the file may come from anywhere, so:

- **Nothing leaves your computer.** There's no network code, no account and no telemetry.
- **Bounded input:** at most 32 KB, 200 characters a line, 40 items and 8 movable bills, and every amount, date and day count has a range. Reading stops at the limit, so `/dev/zero` is refused, and only regular files are opened. Invalid UTF-8 is refused.
- **Strict text:** names must match an allow-list. Control characters, terminal escape codes and invisible bidirectional characters are refused, so nothing printed can hijack your terminal. Error messages give a line number and never repeat your data, and the file name is cleaned before printing.
- **Exact money:** all amounts are whole cents in integers, never floating-point dollars.
- **Bounded work:** the search stops after 2 million steps (a few seconds) and says so if it does.
- **Minimal supply chain:** no runtime dependencies. The only dev dependencies, TypeScript and Node's type definitions, are pinned, and `npm audit` reports 0 vulnerabilities. TypeScript runs in its strictest settings.

**Known limits:** it plans with the numbers you give it, so estimates of everyday spending matter. It's arithmetic, not financial advice.
